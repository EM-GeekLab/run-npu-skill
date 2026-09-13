# 数据源与数据卷

`--mount <类型>:<挂载点>[,键=值…][,ro]`，可重复。**整段创建后不可修改**（CRD 拒绝任何增删改），
"再挂一个盘"= 重建负载。挂载点必须是非根绝对路径、彼此不重叠。

| 类型 | 必填键 | 可选键 | 备注 |
|---|---|---|---|
| `pvc` | `name=` | `subpath=` | ⚠️ **PVC 必须带 `npu.run/project-id=<项目slug>` 标签**，否则被拒为 `PersistentVolumeClaimNotFound`（授权门槛，不是真的不存在；`kubectl label pvc <名> npu.run/project-id=<slug>`） |
| `datavolume`（别名 `dv`） | `name=`（**集群卷名 cr_name**，`runnpu datavolume list` 查，不是显示名） | | 归属项目可读写；共享清单内 / 全平台共享**必须加 `,ro`**（否则 422 `cross_project_readonly`） |
| `newvolume` | `pool=` `size=` | `persistency=workload\|project` `accessmode=` | 计入项目存储配额；`project` 持久卷在负载删除后保留 |
| `nfs` | `server=` `path=` | | 直接投影，用前确认节点能挂 |
| `s3` | `bucket=` `credential=` | `prefix=` | credential 是同项目登记的凭据名 |
| `git` | `url=` | `revision=` `depth=` `credential=` | |
| `hostpath` | `path=` | `kind=` | 高危：需 `workloads:hostpath` 权限 + 项目策略白名单（前缀+kind+读写位），写入还要策略放行 |
| `emptydir` | | `size=` `medium=disk\|memory` | 只有 `medium=memory` 计内存 |
| `configmap` / `secret` | `name=` | | 逐键投影（items[]）CLI 表达不了，走 `runnpu api` |

## 受管卷（newvolume / 工作区）要点

- `--workspace-pool` + `--workspace-gib` 是 `newvolume:/workspace,…` 的顺手写法。
- 卷根由平台初始化为 `root:20000` mode 770 + ACL，容器进程带补充组 20000——**restricted 非 root 也可写**。
- 容量计入项目在该池的存储配额（`runnpu project quota get` 看余量；不足 422 `exceeds_quota`）。
- `persistency=workload` 随负载删除；`project` 保留为项目持久卷（删除走回收流程，可能有延迟）。

## 数据卷命令组

```bash
runnpu datavolume list [--project X]     # 「集群卷名」列 = mount 时的 name
runnpu datavolume create --project main --name 训练集A --pool shared-cephfs --capacity-gib 100 \
  [--share proj-b --share proj-c] [--reclaim-policy retain|delete]
runnpu datavolume update <集群卷名> [--name …] [--share …整体替换]
runnpu datavolume delete <集群卷名> --yes    # 有活跃绑定 409 has_active_bindings；--force 跳过
```

`state` 从 creating 收敛到 ready 才能被挂；`cleanup_blocked` / `conflict` 是一等异常态，看 `state_note`。
