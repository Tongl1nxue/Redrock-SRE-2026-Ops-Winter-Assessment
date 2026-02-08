# 运维部分考核

**姓名**：向伽立  
**学号**：2025212606  

## 项目简介

本项目编写了一个 Linux Shell 脚本 `network.sh`，用于在办公网络和生产网络之间进行自动化切换。脚本实现了网络配置管理、防火墙策略部署、自动违规检测及回滚功能，满足考核的所有基础要求及进阶要求。


##  环境依赖

- **操作系统**：Kali Linux 基于 Debian/Ubuntu
- **权限要求**：需要 `root` 权限执行 
- **核心工具**：`ifupdown` (网络管理), `iptables` (防火墙), `cron` (定时任务), `ping` (连通性检测)

##  主要内容

### 1. 赋予执行权限

```bash
chmod +x network.sh
```

### 2.使用方法

**办公模式**：自动获取 IP，清除防火墙，移除监控任务

```bash
sudo ./network.sh dhcp
```

**生产模式**：配置静态 IP (172.22.146.150)，开启防火墙隔离，添加自动监控

```bash
sudo ./network.sh static
```

**检测模式**：(仅供 Crontab 调用) 检测公网连通性，违规自动回滚

```bash
sudo ./network.sh check
```

**系统回滚**：恢复至实验前的初始网络配置

```bash
sudo ./network.sh rollback
```

##  任务实现详解

### 任务一：基础网络配置

**实现原理**： 脚本通过 `cat <<EOF` 重定向写入 `/etc/network/interfaces` 文件，并使用 `systemctl restart networking` 重启服务。

- **DHCP 模式**： 配置 `iface eth0 inet dhcp`，确保办公环境自动获取地址。
- **Static 模式**： 配置题目要求的静态参数：
  - IP: `172.22.146.150`
  - Netmask: `255.255.255.0`
  - Gateway: `172.22.146.1`
  - DNS: `172.22.146.53`, `172.22.146.54`

### 任务二：生产网络隔离

**实现原理**： 在切换到 `static` 模式时，脚本会自动应用 `iptables` 规则。采用“白名单机制”，默认策略设为 DROP。

**使用的核心指令**：

1. **清空旧规则**：`iptables -F`
2. **放行本地回环**：`iptables -A OUTPUT -o lo -j ACCEPT`
3. **放行同一网段**：`iptables -A OUTPUT -d 172.22.146.0/24 -j ACCEPT`
4. **放行内部大网**：`iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT`
5. **拒绝所有其他流量 (公网)**：`iptables -P OUTPUT DROP`

### 任务三：自动检测与切换

**实现原理**：

1. **定时任务管理**：
   - 在 `static` 模式下，脚本自动将 `* * * * * /path/to/network.sh check` 写入 Crontab。
   - 在 `dhcp` 模式下，自动移除该条目。
2. **检测逻辑**：
   - 使用 `ping -c 1 -W 2 8.8.8.8` 检测外网连通性。
   - **判定违规**：如果 Ping 通（返回 0），说明防火墙失效或被绕过。
   - **自动响应**：脚本记录 `[CRITICAL]` 日志，并立即调用 `dhcp` 模式函数强制回滚。

------

## 日志与验证

为了方便排查错误和定位问题，所有关键操作均会记录在日志文件中。

- **日志路径**：`/var/log/network.log`

- **日志记录示例**：

  Plaintext

  ```
  2026-02-08 12:32:42 [INFO] >>> 切换操作：生产网络模式 (Static)
  2026-02-08 12:36:38 [CRITICAL] 违规警告：生产环境检测到公网连通！正在强制回滚...
  2026-02-08 12:39:27 [SUCCESS] 网络配置已更新为 dhcp 模式
  ```

