# Linux原生规则集cache公开夹具

读者：网络组件维护者。接口/边界改变时更新；MLPA动态事实只在RPR唯一状态维护。

## 用途与明确非用途

[入口](../scripts/linux_rule_cache_fixture.py)只验证现装sing-box 1.13.14的原生remote-rule cache：公开SRS由native producer取得、保存并正常退出，然后由另一个native consumer在禁止IP/IPC代理socket的条件下读回。独立空cache必须因策略拒绝而初始化失败。

它不是安装器、Root诊断器、真实cache查看器或生产修复命令。不接受秘密profile、登记、keyring或live DB参数；不能对旧cache“试开”。现装cache打开本身可能写、清理或重置文件。空inbounds本身也不是运行真实Root profile的安全证明。

## 输入

只支持实际非Root Linux、全部UID相同且非0、Eff/Prm/Inh/Amb四个capability集合全零、小端x86_64/aarch64。程序文件须为外部固定SHA的canonical、Root所属、单链接、不可组/世界写ELF，所有父目录亦可信；精确native版本须为1.13.14。不扫描仓库fallback或读取实际凭据。

调用者提供一个私有0700的公开资产目录，仅按明确名称读取：

- `domain.srs`：批准的公开geosite-cn binary。
- `ip.srs`：批准的公开geoip-cn binary。
- `spec.json`：当前用户0600普通单链接文件，只声明两个工件的外部批准SHA与长度：

```json
{
  "domain": {"sha256": "EXTERNALLY_APPROVED_64_HEX", "bytes": 57617},
  "ip": {"sha256": "EXTERNALLY_APPROVED_64_HEX", "bytes": 34259}
}
```

长度是示例观察，不是永久上游大小；每份硬界131072B，缺失/漂移/链接/权限错误拒绝。不能把任意真实配置重命名成输入。

```sh
python3 -I -S -B scripts/linux_rule_cache_fixture.py \
  --binary "$REGISTERED_PUBLIC_BINARY" --binary-sha256 "$APPROVED_BINARY_SHA256" \
  --assets "$OWNED_PUBLIC_ASSET_DIR" --spec "$OWNED_PUBLIC_ASSET_DIR/spec.json"
```

所有变量须由当前受信来源取得，不能复制历史主机/路径当运行条件。不是sudo命令；Root拒绝。

## 受限执行与真实断言

1. fixture只新建自己的0700临时目录；HOME/XDG/TMP与绝对配置/cache路径指向此目录，不接受原profile。native配置只含typed UDP文档地址DNS、空inbounds、单direct、两个remote/binary规则集及其cache。无TUN、endpoints、NTP、Clash API；fake-IP/RDRC持久化关闭。
2. 一个有限loopback HTTP供给器只服务两份经SHA核对的既有公开字节，每份最多一次，无ETag/redirect/外部fetch。数据的原上游采样时间与本次native保存时间不同，不能称新上游下载。
3. producer必须ready、正常SIGTERM关闭并实际供给两份资产。仅DB文件存在不算成功：原生保存错误未必阻止启动。
4. 供给器关闭、线程join后，consumer恢复批准公网URL，保持相同synthetic tag/format/cache_id。preexec设置不可撤销no_new_privs及seccomp；close_fds，无继承socket。过滤器只允许NETLINK_ROUTE socket供原生接口监视，拒绝其他所有socket domain、socketpair、io_uring与x32 ABI，不同audit架构终止。先用实际内核selftest确认IPv4/IPv6/UNIX/PACKET/VSOCK及io_uring均EPERM，再核实际ready的native PID处于seccomp2、no_new_privs1、四UID与已核非Root父UID一致且Eff/Prm/Inh/Amb四集合全零。
5. 缓存consumer必须ready并正常关闭；另一个全新空DB在相同限制下必须不ready、非零退出且明确initial rule-set＋EPERM，才形成可区分正负证据。失败不扩大网络/权限、不安装依赖、不换无隔离回退。
6. 每个native阶段有界，捕获输出有界且不导出raw log；线程、子进程、临时配置及DB退出回收。新DB摘要只绑定本次公开fixture输入，不是生产接受凭证。

这是特定可信native binary／公开配置的网络限制，不是通用恶意程序或文件系统沙箱，更不是秘密Root profile的副作用证明。

## 不能从通过结果推断的事项

固定`cache_id=mlpa-public-fixture-only-v1`和`fixture-domain/ip`故意不冒充真实profile。fixture DB不留作采用工件；不得为适配它去改真实tag/cache_id。真实Owner采用仍须先在原生本机内核对当前源/登记、精确cache_id（空值不等于default）、tag/URL/format/批准SRS绑定、cache策略、有效path/基准、ownership/链接、既存数据及并发消费者；未知保持未知。

源码交付≠实际采用，cache兜底≠上游网络恢复，native ready≠认证/业务通过。真实规则集初始化、Node网络、备用新登录、四网络组合和至少24h分别验收。不得调用本fixture打开未知live DB，也不以MainPID0声称auto-restart消费者没有并发。

## 检查与来源

受影响host-independent检查入口：

```sh
python3 -B -m unittest discover -s tests -p 'test_linux_rule_cache_fixture.py' -v
```

合成BPF模型不替代实际Linux内核selftest／native producer-consumer；旧SRS解编译不重复作为cache验证。

- [v1.13.14 cache配置](https://github.com/SagerNet/sing-box/blob/v1.13.14/docs/configuration/experimental/cache-file.md)
- [v1.13.14 remote初始化、保存与更新](https://github.com/SagerNet/sing-box/blob/v1.13.14/route/rule/rule_set_remote.go)
- [v1.13.14 cache命名空间与原生DB操作](https://github.com/SagerNet/sing-box/blob/v1.13.14/experimental/cachefile/cache.go)
- [Linux seccomp继承与ABI](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)
- [no_new_privs](https://www.kernel.org/doc/html/latest/userspace-api/no_new_privs.html)
