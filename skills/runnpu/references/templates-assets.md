# 模板与资产速查

模板 = **整张创建表单**的值拷贝；资产 = **单个配置段**的值拷贝。两者都是「值」不是「链接」：
展开时把值抄进创建请求，之后改模板不影响已建负载。

## 模板

```bash
runnpu template list [--type training-env] [--scope cluster|project] [--project X] [-q 关键词] [--all]
runnpu template get <名称或ID>                       # payload 就是创建请求的字段
runnpu template create --name N --type T --payload @tpl.json [--description D] [--scope project --project X]
runnpu template update <名称或ID> [--name …] [--payload @tpl.json]     # PUT 整体替换，没给的字段用现值兜底
runnpu template delete <名称或ID> --yes
```

- 列表里 **★ 开头是系统预置**：只读，不能改删，只能照抄一份自己的。
- `--payload` 支持 `@文件` / `-`（stdin）/ 字面 JSON。改现成的最省事：
  `runnpu template get X -o json | jq .payload > tpl.json`，改完 `--payload @tpl.json`。
- `--type` 创建后不可改（类型是模板身份的一部分）。
- 权限不足时 `list` 返回**空列表而不是 403**，所以「空」要说成「没有或没权限」。

### 用模板创建负载

```bash
runnpu workload create --project main --name nb6 --from-template <名称或ID> [--xpu 2] [--mount …] --wait
```

合并规则（CLI 保证，出错会明确报错而不是静默）：

| 情况 | 行为 |
|---|---|
| 命令行没写的字段 | **保留模板值**——`--xpu` 的默认值 1 不会覆盖模板里的 4 |
| 命令行显式写了的字段 | 覆盖模板值。**`--xpu 0`、`--jupyter=false` 这种显式零值也算覆盖** |
| `--mount` 与模板预设的数据源 | 取**并集**；挂载点重复直接报错（不静默覆盖，否则用户以为模板的盘还在） |
| `--type` 与模板类型不一致 | 报错。换模板，不要改类型 |
| 模板里有 CLI 不认识的字段 | 报错并提示升级 CLI——**宁可报错也不丢字段** |

模板的 `pending_fields` 是「使用者提交时要补」的字段：**问用户，不要编**。

## 资产

```bash
runnpu asset list [--kind environment|compute|data-source|credential] [--scope …] [-q 关键词]
runnpu asset get <名称或ID>                          # 凭证的密文永不回显
runnpu asset create --kind K --name N [--subtype S] [--payload @a.json] [--secret KEY=VALUE ...]
runnpu asset update <名称或ID> [--payload @a.json] [--secret KEY=VALUE ...]
runnpu asset delete <名称或ID> --yes
```

- `--secret` 的值支持 `@文件`（推荐：避免密码/私钥进 shell history）：

  ```bash
  runnpu asset create --kind credential --subtype ssh-key --name 部署密钥 \
      --payload '{}' --secret 'ssh-privatekey=@~/.ssh/id_ed25519'
  ```

- 凭证是唯一会离开 `ready` 的资产——它要在项目命名空间里落成 Secret，那一步可能失败；
  `list` 的状态列会带出 `state_note`。
- **没有 `data-volume` 大类**：数据卷背后是真实的一块盘，是独立一等资源，走 `runnpu datavolume`。
- 资产怎么用：environment（镜像 + env）/ compute（池 + 卡数）按段并入创建参数；
  credential / data-source 在挂载里按名引用（如 `--mount s3:/data,bucket=b,credential=<资产名>`）。
