#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>

namespace {

constexpr const char* kHost = "192.168.0.1";
constexpr uint16_t kPort = 1900;
constexpr const char* kPath = "/ifc";
constexpr const char* kNs =
    "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1";

volatile std::sig_atomic_t g_stop = 0;

void on_sigint(int) { g_stop = 1; }

std::string xml_tag(const std::string& xml, const char* tag) {
    const std::string open = std::string("<") + tag + ">";
    const auto pos = xml.find(open);
    if (pos == std::string::npos) {
        throw std::runtime_error(std::string("missing <") + tag + ">");
    }
    const auto start = pos + open.size();
    const auto end = xml.find('<', start);
    if (end == std::string::npos) {
        throw std::runtime_error(std::string("unclosed <") + tag + ">");
    }
    return xml.substr(start, end - start);
}

std::uint64_t xml_u64(const std::string& xml, const char* tag) {
    return std::stoull(xml_tag(xml, tag));
}

std::string http_post(const std::string& body, const std::string& soap_action,
                      int timeout_sec) {
    const int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        throw std::runtime_error("socket");
    }

    timeval tv{};
    tv.tv_sec = timeout_sec;
    tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kPort);
    if (inet_pton(AF_INET, kHost, &addr.sin_addr) != 1) {
        ::close(fd);
        throw std::runtime_error("inet_pton");
    }
    if (connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        ::close(fd);
        throw std::runtime_error("connect 192.168.0.1:1900");
    }

    std::ostringstream req;
    req << "POST " << kPath << " HTTP/1.1\r\n"
        << "Host: " << kHost << ":" << kPort << "\r\n"
        << "Content-Type: text/xml; charset=\"utf-8\"\r\n"
        << "SOAPAction: \"" << kNs << "#" << soap_action << "\"\r\n"
        << "Content-Length: " << body.size() << "\r\n"
        << "Connection: close\r\n"
        << "\r\n"
        << body;
    const auto raw = req.str();
    if (::send(fd, raw.data(), raw.size(), 0) < 0) {
        ::close(fd);
        throw std::runtime_error("send");
    }

    std::string resp;
    char buf[2048];
    for (;;) {
        const ssize_t n = ::recv(fd, buf, sizeof(buf), 0);
        if (n < 0) {
            ::close(fd);
            throw std::runtime_error("recv");
        }
        if (n == 0) {
            break;
        }
        resp.append(buf, static_cast<size_t>(n));
    }
    ::close(fd);

    const auto hdr_end = resp.find("\r\n\r\n");
    if (hdr_end == std::string::npos) {
        throw std::runtime_error("bad HTTP response");
    }
    if (resp.compare(0, 12, "HTTP/1.1 200") != 0 &&
        resp.compare(0, 12, "HTTP/1.0 200") != 0) {
        throw std::runtime_error("HTTP not 200");
    }
    return resp.substr(hdr_end + 4);
}

std::string soap(const char* action, int timeout_sec) {
    std::string body;
    body += "<?xml version=\"1.0\"?>";
    body += "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" ";
    body += "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">";
    body += "<s:Body><u:";
    body += action;
    body += " xmlns:u=\"";
    body += kNs;
    body += "\"></u:";
    body += action;
    body += "></s:Body></s:Envelope>";
    return http_post(body, action, timeout_sec);
}

std::pair<std::uint64_t, std::uint64_t> read_totals(int timeout_sec) {
    const auto sent_xml = soap("GetTotalBytesSent", timeout_sec);
    const auto recv_xml = soap("GetTotalBytesReceived", timeout_sec);
    return {xml_u64(sent_xml, "NewTotalBytesSent"),
            xml_u64(recv_xml, "NewTotalBytesReceived")};
}

std::uint64_t unwrap(std::uint64_t prev, std::uint64_t cur) {
    if (cur >= prev) {
        return cur - prev;
    }
    if (prev < (1ull << 32)) {
        return cur + (1ull << 32) - prev;
    }
    return cur;
}

std::string fmt_bytes(double value, const char* const* units, int n) {
    int i = 0;
    for (; i + 1 < n && value >= 1024.0; ++i) {
        value /= 1024.0;
    }
    char buf[64];
    if (i == 0) {
        std::snprintf(buf, sizeof(buf), "%d %s", static_cast<int>(value), units[i]);
    } else {
        std::snprintf(buf, sizeof(buf), "%.2f %s", value, units[i]);
    }
    return buf;
}

std::string fmt_total(std::uint64_t n) {
    static const char* units[] = {"B", "KB", "MB", "GB", "TB"};
    return fmt_bytes(static_cast<double>(n), units, 5);
}

std::string fmt_rate(double bytes_per_sec) {
    if (bytes_per_sec < 0) {
        bytes_per_sec = 0;
    }
    static const char* units[] = {"B/s", "KB/s", "MB/s", "GB/s"};
    return fmt_bytes(bytes_per_sec, units, 4);
}

}  // namespace

int main() {
    std::signal(SIGINT, on_sigint);

    constexpr int timeout_sec = 4;
    std::uint64_t prev_sent = 0;
    std::uint64_t prev_recv = 0;
    try {
        const auto first = read_totals(timeout_sec);
        prev_sent = first.first;
        prev_recv = first.second;
    } catch (const std::exception& e) {
        std::cerr << "连不上路由器 UPnP：" << e.what() << "\n"
                  << "控制地址：http://" << kHost << ":" << kPort << kPath << "\n";
        return 1;
    }

    auto prev_t = std::chrono::steady_clock::now();
    std::cout << "来源：UPnP IGD 累计字节（不登录网页）\n"
              << "Ctrl+C 退出\n\n"
              << std::flush;

    while (!g_stop) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        if (g_stop) {
            break;
        }
        try {
            const auto now_tot = read_totals(timeout_sec);
            const auto now = std::chrono::steady_clock::now();
            const double dt =
                std::chrono::duration<double>(now - prev_t).count();
            if (dt <= 0) {
                continue;
            }
            const double up = static_cast<double>(unwrap(prev_sent, now_tot.first)) / dt;
            const double down =
                static_cast<double>(unwrap(prev_recv, now_tot.second)) / dt;
            prev_sent = now_tot.first;
            prev_recv = now_tot.second;
            prev_t = now;

            std::cout << "\x1b[H\x1b[J"
                      << "路由器 WAN\n"
                      << "  上传  " << fmt_rate(up) << "    累计  "
                      << fmt_total(now_tot.first) << "\n"
                      << "  下载  " << fmt_rate(down) << "    累计  "
                      << fmt_total(now_tot.second) << "\n\n"
                      << "间隔 " << dt << "s   http://" << kHost << ":" << kPort
                      << kPath << "\n"
                      << std::flush;
        } catch (const std::exception& e) {
            std::cout << "\r读取失败：" << e.what() << "          " << std::flush;
        }
    }
    std::cout << "\n已退出\n";
    return 0;
}
