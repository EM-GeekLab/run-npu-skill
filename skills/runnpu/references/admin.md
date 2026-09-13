# 管理面：项目 / 配额 / 成员 / 用户 / 设置 / 审计

## 项目与配额

```bash
runnpu project list / get <slug>
runnpu project create --slug asr --name 语音识别 --pool ascend910b4 --guaranteed 4 --limit 4 \
  --storage-pool shared-cephfs --storage-gib 200
runnpu project delete asr --yes            # 项目里不能有未终止负载；负载卡 Terminating 时会失败（见 troubleshooting）
runnpu project quota get asr               # 声明的配额 + 集群侧实际（cluster 段空 = 配额没落到集群）
runnpu project quota set asr --pool ascend910b4=8,4 --storage-pool shared-cephfs=500
runnpu project quota set asr --priority normal --workload-type workspace
runnpu project repair asr --action resync  # 配额重新物化；release_grant_finalizer 是破窗动作，必须 --yes
```

- 单位是**卡**：`--pool <池>=<保底>,<可借增量>`；借用部分可被抢占。
- `quota set` 是**整份替换**：给了 `--pool` 就替换全部池段——改一个池前先 `quota get`，把要保留的一并传入。
- 建项目前先 `runnpu cluster get` 看池剩余；集群总卡被占满时新项目配额会被拒（负载报 QuotaGrantNotFound）。

## 项目成员

```bash
runnpu project members list asr
runnpu project members add asr --user alice@example.com --role 项目管理员   # 角色名 runnpu api GET /roles
runnpu project members remove asr --user alice@example.com --yes           # 默认移除全部角色；--role 只删一个
```

## 用户与 Access Key

```bash
runnpu user list [--q alice] [--type robot] [--status disabled]
runnpu user create --type local --email alice@example.com --display-name Alice   # 初始密码只返回一次，原样转给用户
runnpu user create --type robot --name ci-bot --display-name "CI 机器人" --owner admin@example.com
runnpu user disable|enable alice@example.com
runnpu user access-key create ci-bot --name pipeline --expires-in-days 90        # 明文 token 只返回一次
runnpu user access-key list|revoke …
runnpu access-key list|create|revoke …    # 我自己的
```

- API token **不能**再签发 token（403）：`access-key create` 只在会话登录下可用，机器人 key 由管理员签发。
- 禁用账号后其登录报 401 `account_disabled`；已有会话/token 同样被拒。

## 系统设置与审计

```bash
runnpu settings get
runnpu settings set storage.show_unnamed_pools true    # 点路径 → 嵌套 PATCH，自动解析 bool/数字
runnpu audit list --limit 20 [--actor a@b.com] [--action workload.] [--target-kind user]   # --action 前缀匹配
```

## 未封装端点

```bash
runnpu api GET /projects/form-meta        # 池容量、其它项目已分配
runnpu api GET '/overview/trends?range=24h'
runnpu api GET /roles
runnpu api POST /workloads -d '{...}'     # CLI 表达不了的字段（探针/autoscaling/configmap items…）
```

路径 = `api/openapi.yaml` 的 path 去掉 `/api/v1` 前缀。
