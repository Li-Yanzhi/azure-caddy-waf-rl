# Caddy Cluster with Azure DDoS Protection, WAF & Rate Limiting

[English](README.md)

基于 Terraform 的 Azure 基础设施部署，实现高可用的 Caddy 反向代理集群，集成 DDoS 防护、WAF 和限流功能。

## 架构概览

![架构图](architecture.png)


### 组件职责

| 层级 | 组件 | 职责 |
|------|------|------|
| L3/L4 | Azure DDoS Protection | 大流量清洗、攻击缓解 |
| L4 | Standard Load Balancer | TCP 负载均衡、健康检查 |
| L7 | Caddy + Coraza WAF | TLS 终止、WAF 检测/拦截 |
| L7 | Caddy Rate Limit | 限流、防刷、配额管理 |
| 存储 | Azure Redis Cache | TLS 证书跨实例共享 (可选) |
| 存储 | Azure Files | WAF 规则、配置文件共享 |

## 目录结构

```
lb/
├── main.tf                      # 主配置文件
├── variables.tf                 # 变量定义
├── outputs.tf                   # 输出定义
├── terraform.tfvars.example     # 示例变量文件
├── modules/
│   ├── network/                 # 网络模块 (VNet, NSG, DDoS, PIP)
│   ├── storage/                 # 存储模块 (Storage Account, Azure Files)
│   ├── keyvault/                # Key Vault 模块
│   ├── redis/                   # Redis 模块 (可选，用于证书共享)
│   ├── loadbalancer/            # 负载均衡器模块
│   └── vmss/                    # VMSS 模块 (Caddy 集群)
│       └── templates/
│           ├── cloud-init.yaml  # VM 初始化脚本
│           ├── caddy-config.json # Caddy 配置
│           └── coraza-config.conf # WAF 配置
└── scripts/
    ├── rolling-update.sh        # 滚动更新脚本
    ├── deploy-crs.sh            # 部署 OWASP CRS
    ├── waf-mode.sh              # WAF 模式切换
    └── check-health.sh          # 健康检查脚本
```

## 快速开始

### 1. 准备工作

```bash
# 安装 Terraform (>= 1.5.0)
# 安装 Azure CLI 并登录
az login
az account set --subscription <your-subscription-id>
```

### 2. 配置变量

```bash
# 复制示例配置
cp terraform.tfvars.example terraform.tfvars

# 编辑配置
vim terraform.tfvars
```

必填变量：
- `domain_name`: 您的域名 (例如 `example.com`)
- `acme_email`: ACME 证书注册邮箱
- `upstream_servers`: 上游服务器列表
- `admin_ssh_public_key`: SSH 公钥 (可选，不填则自动生成)

可选变量：
- `rate_limit_storage_backend`: 存储后端选择 (`azure_files` 或 `redis`，默认 `azure_files`)

### 3. 部署

```bash
# 初始化
terraform init

# 预览
terraform plan

# 部署
terraform apply
```

### 4. DNS 配置

部署完成后，将域名指向输出的公网 IP：

```bash
# 获取公网 IP
terraform output public_ip_address
```

## 存储后端配置

### 存储后端选择

Caddy 的 storage 模块用于存储 TLS 证书和 ACME 数据。支持两种后端：

| 后端 | 配置值 | 说明 | 适用场景 |
|------|--------|------|----------|
| Azure Files | `azure_files` | 使用文件系统存储 | 默认选项，简单可靠 |
| Azure Redis | `redis` | 使用 Redis 存储 | 多实例证书快速同步 |

```hcl
# terraform.tfvars
rate_limit_storage_backend = "redis"  # 或 "azure_files"
```

### Redis 存储配置

选择 `redis` 后，Caddy 配置自动使用 Azure Redis Cache：

```json
{
  "storage": {
    "module": "redis",
    "host": ["redis-caddy-xxx.redis.cache.windows.net"],
    "port": ["6380"],
    "tls_enabled": true,
    "key_prefix": "caddy"
  }
}
```

**注意**：Rate Limit 数据仍在内存中管理，每个 Caddy 实例独立计数。Redis 主要用于 TLS 证书共享。

### Azure Files 共享目录

无论使用哪种存储后端，Azure Files 仍用于存储 WAF 规则。

挂载路径: `/mnt/caddyshare`

```
caddyshare/
├── caddy-data/      # 证书数据 (仅 azure_files 模式使用)
├── waf/
│   ├── crs/         # OWASP CRS 规则
│   └── custom/      # 自定义 WAF 规则
└── releases/        # 配置版本 (用于回滚)
```

## WAF 配置

使用 [Coraza WAF](https://coraza.io/) 模块，通过 Caddy JSON 配置内联规则。

### 当前启用的规则

| 规则 ID | 类型 | 描述 |
|---------|------|------|
| 942100 | SQL 注入 | 使用 `@detectSQLi` 检测 SQL 注入攻击 |
| 941100 | XSS 攻击 | 使用 `@detectXSS` 检测跨站脚本攻击 |
| 930100 | 路径遍历 | 检测 `../` 路径遍历尝试 |
| 932100 | 命令注入 | 检测 `;` `|` `&&` 等命令注入符号 |
| 913100 | 扫描器检测 | 阻止 sqlmap、nikto、nmap 等扫描工具 |

### 配置示例

```json
{
  "handler": "waf",
  "directives": "SecRuleEngine On\nSecRule ARGS \"@detectSQLi\" \"id:942100,phase:2,deny,status:403,log,msg:SQL Injection\"\nSecRule ARGS \"@detectXSS\" \"id:941100,phase:2,deny,status:403,log,msg:XSS Attack\"\nSecRule REQUEST_URI \"@contains ../\" \"id:930100,phase:1,deny,status:403,log,msg:Path Traversal\"\nSecRule ARGS \"@rx (;|\\||&&)\" \"id:932100,phase:2,deny,status:403,log,msg:Command Injection\"\nSecRule REQUEST_HEADERS:User-Agent \"@rx (?i)(sqlmap|nikto|nmap)\" \"id:913100,phase:1,deny,status:403,log,msg:Scanner Detected\""
}
```

### 自定义规则

可在 `directives` 字符串中添加自定义 SecRule：

```
# 白名单特定路径
SecRule REQUEST_URI "@beginsWith /api/webhook" \
    "id:100001,phase:1,pass,nolog,ctl:ruleRemoveById=941100"

# 阻止特定 User-Agent
SecRule REQUEST_HEADERS:User-Agent "@contains BadBot" \
    "id:100002,phase:1,deny,status:403,log,msg:'Blocked bad bot'"
```

### 查看日志

```bash
# Caddy 日志（包含 WAF 事件）
journalctl -u caddy -f
```

## 限流配置

Caddy 配置中已包含两层限流：

| 规则 | Key | 窗口 | 限制 | 说明 |
|------|-----|------|------|------|
| per_ip | `{remote_host}` | 1分钟 | 100 请求 | IP 级别通用限制 |
| per_user | `{header.X-User-Id}` | 1分钟 | 10 请求 | 基于 Header 的用户限制 |

### 配置示例

```json
{
  "handler": "rate_limit",
  "rate_limits": [
    {
      "key": "{remote_host}",
      "rate": "100r/m"
    },
    {
      "key": "{header.X-User-Id}",
      "rate": "10r/m"
    }
  ]
}
```

修改限流参数后需运行滚动更新。

## 滚动更新

### 更新配置

```bash
# 准备新配置
vim /etc/caddy/config.json

# 执行滚动更新
./scripts/rolling-update.sh \
    -g rg-caddy-cluster \
    -v vmss-caddy-xxx \
    -c /etc/caddy/config.json
```

### 更新 WAF 规则

```bash
# 部署新版本 CRS
./scripts/deploy-crs.sh -s <storage-account> -v 4.0.0

# 滚动重载
./scripts/rolling-update.sh -v <vmss-name> -c /etc/caddy/config.json
```

## 监控与日志

### 日志位置

| 日志 | 路径 | 说明 |
|------|------|------|
| 访问日志 | `/var/log/caddy/access.log` | HTTP 请求日志 |
| WAF 日志 | `/var/log/caddy/waf.log` | WAF 事件日志 |
| 审计日志 | `/var/log/caddy/waf-audit.log` | 详细审计日志 |

### Azure Monitor

VMSS 已安装 Azure Monitor Agent，可在 Azure Portal 查看：
- CPU/内存使用率
- 网络流量
- 自定义指标

## 安全建议

1. **Key Vault**: 所有敏感信息存储在 Key Vault
2. **私有端点**: Storage、Key Vault、Redis 均使用私有端点
3. **NSG**: 仅允许必要端口 (80, 443, 22, 6380 内部)
4. **SSH 访问**: 仅 VNet 内可 SSH
5. **Admin API**: 仅监听 localhost (127.0.0.1:2019)
6. **Redis TLS**: 仅启用 SSL 端口 (6380)，禁用非 SSL 端口

## 成本估算

主要成本组件：
- Azure DDoS Protection Standard: ~$2,944/月 (可选，设置 `enable_ddos_protection = false` 禁用)
- Standard Load Balancer: ~$18/月 + 数据处理费
- VMSS (2x Standard_B2s): ~$60/月
- Storage Account (ZRS): ~$2/月 (100GB)
- Key Vault: ~$3/月
- Azure Redis Cache (Basic C0): ~$16/月 (已包含，用于证书共享)

## 安全测试

使用 `scripts/test-security.sh` 脚本测试 Rate Limiting 和 WAF 功能：

```bash
cd scripts
./test-security.sh
```

### 测试项目

| 类别 | 测试项 | 预期结果 |
|------|--------|----------|
| 连通性 | HTTPS 连接 | 200 OK |
| 连通性 | /health 端点 | healthy |
| Rate Limit | X-User-Id (10/min) | 第 11 个请求返回 429 |
| WAF | SQL 注入 (`' OR '1'='1`) | 403 Forbidden |
| WAF | XSS (`<script>`) | 403 Forbidden |
| WAF | 路径遍历 (`../`) | 403 Forbidden |
| WAF | 命令注入 (`;ls`) | 403 Forbidden |
| WAF | 扫描器 User-Agent | 403 Forbidden |
| 正常请求 | 普通浏览器请求 | 200 OK |

### 示例输出

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Test Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Overall Results:
  ┌─────────────────────────────────────┐
  │  Total Tests:  21
  │  Passed:       18
  │  Failed:       3
  └─────────────────────────────────────┘

  ◐ Most tests passed (85%). Some issues may need attention.
```

## 故障排查

### Caddy 服务问题

```bash
# 查看服务状态
systemctl status caddy

# 查看日志
journalctl -u caddy -f

# 测试配置
caddy validate --config /etc/caddy/config.json
```

### Azure Files 挂载问题

```bash
# 检查挂载状态
mount | grep caddyshare

# 重新挂载
systemctl restart mnt-caddyshare.mount
```

### 健康检查失败

```bash
# 本地测试
curl -v http://127.0.0.1/health

# 批量检查
./scripts/check-health.sh -v <vmss-name>
```

## License

MIT
