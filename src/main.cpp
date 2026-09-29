// SPDX-License-Identifier: MIT
#include "anime.hpp"
#include "bridge.hpp"
#include "expressions.hpp"
#include "osc.hpp"
#include "params.hpp"

#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>

namespace {

struct Options {
  std::string target = "127.0.0.1:9000";
  std::string prefix = "/FT";
  std::string source = "/dev/shm/eye-server.mmap";
  bool anime = false;
  bool heuristics = true;
  bool native = false;
  int learn_port = 0;
  std::string gains;
  float lost_at = 0.02f;
};

int usage() {
  std::fprintf(stderr,
               "usage: frameeyeosc [--target HOST:PORT] [--prefix /FT] [--source PATH]\n"
               "                   [--style reference|anime] [--no-heuristics] [--native]\n"
               "                   [--learn-port PORT] [--gains FILE] [--lost-at COV]\n");
  return 2;
}

bool parse(int argc, char **argv, Options &o) {
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--no-heuristics") {
      o.heuristics = false;
      continue;
    }
    if (a == "--native") {
      o.native = true;
      continue;
    }
    if (i + 1 >= argc) {
      return false;
    }
    std::string v = argv[++i];
    if (a == "--target") {
      o.target = v;
    } else if (a == "--prefix") {
      o.prefix = v;
    } else if (a == "--source") {
      o.source = v;
    } else if (a == "--style" && (v == "reference" || v == "anime")) {
      o.anime = v == "anime";
    } else if (a == "--learn-port") {
      o.learn_port = std::atoi(v.c_str());
    } else if (a == "--gains") {
      o.gains = v;
    } else if (a == "--lost-at") {
      o.lost_at = static_cast<float>(std::atof(v.c_str()));
    } else {
      return false;
    }
  }
  if (o.prefix.empty() || o.prefix[0] != '/' || o.prefix.find_first_not_of('/') == std::string::npos) {
    return false;
  }
  return true;
}

int connect_udp(const std::string &target) {
  size_t colon = target.rfind(':');
  if (colon == std::string::npos) {
    return -1;
  }
  std::string host = target.substr(0, colon);
  std::string port = target.substr(colon + 1);
  addrinfo hints{};
  hints.ai_socktype = SOCK_DGRAM;
  addrinfo *res = nullptr;
  if (getaddrinfo(host.c_str(), port.c_str(), &hints, &res) != 0 || res == nullptr) {
    return -1;
  }
  int fd = socket(res->ai_family, SOCK_DGRAM, 0);
  if (fd < 0) {
    freeaddrinfo(res);
    return -1;
  }
  if (connect(fd, res->ai_addr, res->ai_addrlen) != 0) {
    close(fd);
    freeaddrinfo(res);
    return -1;
  }
  freeaddrinfo(res);
  return fd;
}

int listen_udp(int port) {
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0) {
    return -1;
  }
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(static_cast<uint16_t>(port));
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  if (bind(fd, reinterpret_cast<sockaddr *>(&addr), sizeof addr) != 0) {
    close(fd);
    return -1;
  }
  return fd;
}

void send_message(int fd, const frameeyeosc::osc::Message &m) {
  std::vector<uint8_t> bytes = frameeyeosc::osc::encode(m);
  if (send(fd, bytes.data(), bytes.size(), 0) < 0) {
    std::perror("send");
  }
}

long long now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

std::string calib_path() {
  const char *home = std::getenv("HOME");
  std::string dir = std::string(home == nullptr ? "." : home) + "/.config/frameeyeosc";
  mkdir(dir.c_str(), 0755);
  return dir + "/calib.txt";
}

// The anime style: calibrated, blink events, expressive filtered gaze, avatar-matched parameters.
class Anime {
 public:
  explicit Anime(const Options &o) : options_(o), entries_(frameeyeosc::params::fallback_plan(prefix(o))) {
    frameeyeosc::calib_load(calib_path(), calib_);
  }

  void learn(const frameeyeosc::osc::Message &m, long long now) {
    if (frameeyeosc::params::observe(learned_, m)) {
      changed_at_ = now;
    }
  }

  // Adopts a learned parameter list once it has been quiet for 300 ms.
  void adopt(long long now) {
    if (changed_at_ == 0 || now - changed_at_ < 300) {
      return;
    }
    changed_at_ = 0;
    std::vector<std::pair<std::string, std::string>> list = frameeyeosc::params::list(learned_);
    entries_ = list.empty() ? frameeyeosc::params::fallback_plan(prefix(options_)) : frameeyeosc::params::plan(list);
    last_.clear();
    std::fprintf(stderr, "avatar %s: %zu parameters driven of %zu seen\n", learned_.avatar.c_str(), entries_.size(),
                 list.size());
  }

  std::vector<frameeyeosc::osc::Message> messages(const fe_sample &s, const frameeyeosc::Gains &gains, long long now) {
    float dt_s = last_time_ == 0.0 ? 0.011f : static_cast<float>(s.sample_time - last_time_);
    dt_s = std::min(0.1f, std::max(0.0f, dt_s));
    last_time_ = s.sample_time;

    std::array<float, 3> center = frameeyeosc::anime::center_direction(s.gaze[0], s.gaze[1]);
    std::array<float, 2> py = frameeyeosc::anime::pitch_yaw_degrees(center.data());
    pitch_ = frameeyeosc::anime::one_euro_step(pitch_, py[0], dt_s);
    yaw_ = frameeyeosc::anime::one_euro_step(yaw_, py[1], dt_s);
    float gx = frameeyeosc::anime::expressive(1.8f, 30.0f, 1.5f, yaw_.x) / 45.0f;
    float gy = -frameeyeosc::anime::expressive(1.8f, 30.0f, 1.5f, pitch_.x) / 45.0f;

    frameeyeosc::FrameIn in;
    in.left = frameeyeosc::EyeIn{s.openness[0], gx, gy};
    in.right = frameeyeosc::EyeIn{s.openness[1], gx, gy};
    calib_ = frameeyeosc::calib_step(calib_, in);

    float rl = frameeyeosc::anime::relative(calib_.left, in.left.openness);
    float rr = frameeyeosc::anime::relative(calib_.right, in.right.openness);
    bool lost_l = frameeyeosc::anime::eye_lost(s.gaze_covariance[0], options_.lost_at);
    bool lost_r = frameeyeosc::anime::eye_lost(s.gaze_covariance[1], options_.lost_at);
    std::array<float, 2> gated = frameeyeosc::anime::wink_gate(lost_l, lost_r, rl, rr);
    state_ = frameeyeosc::anime::step(tuning_, dt_s * 1000.0f, state_, gated[0], gated[1]);

    frameeyeosc::FrameOut out = frameeyeosc::frame(gains, options_.heuristics, calib_, in);
    out.left = frameeyeosc::anime::style_eye(tuning_, gains, options_.heuristics, calib_.left, in.left.openness,
                                             state_.left, out.left);
    out.right = frameeyeosc::anime::style_eye(tuning_, gains, options_.heuristics, calib_.right, in.right.openness,
                                              state_.right, out.right);

    bool refresh = now - refreshed_at_ >= 1000;
    if (refresh) {
      refreshed_at_ = now;
    }
    if (now - saved_at_ >= 60000) {
      saved_at_ = now;
      frameeyeosc::calib_save(calib_path(), calib_);
    }
    std::vector<frameeyeosc::osc::Message> sent;
    for (const frameeyeosc::params::Entry &e : entries_) {
      frameeyeosc::osc::Message m = frameeyeosc::params::message_for(e, out);
      std::map<std::string, frameeyeosc::osc::Arg>::iterator was = last_.find(e.address);
      if (!refresh && was != last_.end() && was->second == m.args[0]) {
        continue;
      }
      last_[e.address] = m.args[0];
      sent.push_back(m);
    }
    if (options_.native) {
      sent.push_back(frameeyeosc::osc::Message{
          "/tracking/eye/CenterPitchYaw",
          {frameeyeosc::osc::float_arg(-gy * 45.0f), frameeyeosc::osc::float_arg(gx * 45.0f)}});
    }
    return sent;
  }

 private:
  static std::string prefix(const Options &o) {
    std::string p = o.prefix.substr(1);
    return p.empty() || p.back() == '/' ? p : p + "/";
  }

  Options options_;
  std::vector<frameeyeosc::params::Entry> entries_;
  frameeyeosc::params::Learned learned_;
  long long changed_at_ = 0;
  frameeyeosc::FrameCalib calib_;
  frameeyeosc::anime::Tuning tuning_;
  frameeyeosc::anime::State state_;
  frameeyeosc::anime::OneEuro pitch_;
  frameeyeosc::anime::OneEuro yaw_;
  double last_time_ = 0.0;
  long long refreshed_at_ = 0;
  long long saved_at_ = 0;
  std::map<std::string, frameeyeosc::osc::Arg> last_;
};

void drain_learning(int fd, Anime &anime) {
  uint8_t buf[65536];
  for (;;) {
    ssize_t n = recv(fd, buf, sizeof buf, MSG_DONTWAIT);
    if (n <= 0) {
      return;
    }
    long long now = now_ms();
    for (const frameeyeosc::osc::Message &m : frameeyeosc::osc::decode_packet(buf, static_cast<size_t>(n))) {
      anime.learn(m, now);
    }
  }
}

} // namespace

int main(int argc, char **argv) {
  Options o;
  if (!parse(argc, argv, o)) {
    return usage();
  }
  frameeyeosc::Gains gains;
  std::string error;
  if (!o.gains.empty() && !frameeyeosc::gains_load(o.gains, gains, error)) {
    std::fprintf(stderr, "%s\n", error.c_str());
    return 1;
  }
  int fd = connect_udp(o.target);
  if (fd < 0) {
    std::fprintf(stderr, "--target %s did not resolve to an address\n", o.target.c_str());
    return 1;
  }
  int learn_fd = o.learn_port > 0 ? listen_udp(o.learn_port) : -1;
  if (o.learn_port > 0 && learn_fd < 0) {
    std::fprintf(stderr, "cannot listen on UDP %d\n", o.learn_port);
    return 1;
  }
  char err[512];
  fe_source *eyes = fe_open(o.source.c_str(), err, sizeof err);
  if (eyes == nullptr) {
    std::fprintf(stderr, "%s\n", err);
    return 1;
  }
  std::fprintf(stderr, "Reading %s and sending OSC to %s (%s style)\n", o.source.c_str(), o.target.c_str(),
               o.anime ? "anime" : "reference");
  Anime anime(o);
  bool active = false;
  for (;;) {
    fe_sample s;
    int r = fe_next(eyes, o.anime ? 50 : 1000, &s, err, sizeof err);
    if (r < 0) {
      std::fprintf(stderr, "%s\n", err);
      fe_close(eyes);
      return 1;
    }
    long long now = now_ms();
    if (learn_fd >= 0) {
      drain_learning(learn_fd, anime);
      anime.adopt(now);
    }
    bool valid = r == 1 && frameeyeosc::sample_valid(s);
    if (valid && o.anime) {
      for (const frameeyeosc::osc::Message &m : anime.messages(s, gains, now)) {
        send_message(fd, m);
      }
      continue;
    }
    if (valid) {
      for (const frameeyeosc::osc::Message &m : frameeyeosc::eye_messages(s, o.prefix)) {
        send_message(fd, m);
      }
      active = true;
      continue;
    }
    if (!active) {
      continue;
    }
    send_message(fd, frameeyeosc::tracking_active(o.prefix, false));
    active = false;
  }
}
