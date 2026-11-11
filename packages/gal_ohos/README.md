# gal_ohos

Gal 的独立 HarmonyOS 原生平台实现，通过既有 `gal` MethodChannel 对接统一 Dart API。
公开平台包版本为 1.0.0，无 Gal Dart 包依赖，因此主包和平台包的依赖关系保持单向。

## 功能与权限

- `putImage`、`putImageBytes`、`putVideo` 使用系统 `showAssetsCreationDialog`，每次保存由用户确认。
- `hasAccess()` 与 `requestAccess()` 表示默认交互保存入口可用，普通应用使用这条路径无需持久图库授权；返回 true 不表示永久读写图库权限。
- `toAlbum: true` 返回 false，自定义 `album` 保存明确抛出 `UNEXPECTED`，附带不支持自定义相册的说明。
- 用户取消保存映射为 `GalExceptionType.accessDenied`，空间不足映射为 `notEnoughSpace`。
- 图片字节由系统图像解码器识别格式，临时文件位于 App 沙箱并在调用结束后清理。
- 插件通过 AbilityAware 获取有效 UIAbilityContext，Ability 分离前停止新的弹窗；用户确认后的文件复制会完成已授权写入。
- 成功返回发生在文件复制并同步完成后，失败时关闭文件并尽力清理本次创建的目标，保留原始错误。
- `open()` 使用公开 `ohos.want.action.viewData` 和 image/* 能力解析，设备没有相应处理器时返回明确的 `UNEXPECTED`。此项设备相关能力需真机验收。

消费 App 的 module.json5 需在 abilities 中配置 label 与 icon（Flutter 默认模板通常已具备），系统确认弹窗依赖这些应用信息。

SDK 下限为 API12。当前 SDK 将图库全量读写权限列为 system_basic，本包通过系统保存确认能力完成普通 App 保存，不声明这些受限权限。

## 来源

标准 Gal 来源为 `https://github.com/natsuk4ze/gal` 的 v2.3.3 标签，提交
`5a36aff5b0669690cd94a9443a6eed64d4c7cc78`。本包 ArkTS 实现为本次新开发。
本次检查 pub.dev 的 gal_ohos API 返回 404，首次发布版本拟为 1.0.0；审核 CPF-Flutter/fluttertpc_gal 的默认分支
`4e29896c2408b63822524ad7764d3aeeece7826d` 未发现鸿蒙实现，公开 tag 和分支名称
也未标识鸿蒙适配版本。它与官方发布标签仅有示例 Android Gradle 配置差异，Dart lib tree 相同。
当前方案未引用该镜像，其审计副本保留于临时审核目录，公开实现维护于 https://github.com/wangweicheng7/gal 的 packages/gal_ohos，保留标准 Gal 的 Git 历史。
上游许可证随包保留。

官方资料与已安装 SDK 接口用于实现，包括 photoAccessHelper.showAssetsCreationDialog、
ImageSource.getImageInfo、fileIo.copyFile 和 fsync。发布前需完成手机上的系统确认、
取消、真实写入及图库打开行为验收，单元测试和 HAP 构建不替代真机验收。

最小真机验收覆盖：PNG 取消后返回 accessDenied；确认后图库能打开新增图片；
不存在/空文件和自定义相册在弹窗前失败；本地视频保存成功；记录 Gal.open() 的设备表现。
使用独立签名测试应用；签名和 bundleName 复用生产应用的探针只用于构建，安装前需单独确认覆盖范围。

## 使用

官方 Gal 尚未内置鸿蒙声明时，App 同时声明主包与平台包：

```yaml
dependencies:
  gal: ^2.3.3
  gal_ohos: ^1.0.0
```

平台包通过 `implements: gal` 和原生 MethodChannel `gal` 注册，无需修改 Gal 的 Dart API。
若使用已经声明 `ohos.default_package: gal_ohos` 的私有 Gal 主包，只依赖主包即可。
平台包不依赖 Gal 主包，避免循环依赖。

## 发布

源码位于 fork 的 `packages/gal_ohos`，适配分支 `feat/gal-ohos-1.0.0` 从
官方 `v2.3.3` 创建；fork 的 `main` 保留原意。原始 Gal 根包不发布到 pub.dev。

公开发布前在 fork 根目录审核并提交、推送当前分支，使 pubspec 中 repository 指向的源码可访问：

```sh
git add .gitignore .fvmrc README.md packages/gal_ohos
git commit -m "feat: 新增 Gal 鸿蒙联邦插件"
git push -u origin feat/gal-ohos-1.0.0
```

在仓库根目录执行 `fvm use ohos/3.44.9+ohos-1.0.0-beta` 后：

```sh
cd packages/gal_ohos
export PUB_HOSTED_URL=https://pub.dev
fvm flutter pub get --no-example
fvm dart analyze lib
fvm dart pub publish --dry-run
fvm dart pub publish
```

`publish_to` 显式指定 pub.dev，避免开发机的私仓环境变量改变上传目标。
首次发布需要发布者登录 Pub 账户并完成浏览器授权；发布与 GitHub 推送均由负责人执行。

随后在私有 Gal 主包中以 `hosted: https://pub.dev`、`version: ^1.0.0` 引用本包，
补充 `ohos.default_package: gal_ohos`，完成真实 hosted 依赖解析后再发布主包到私仓。
平台包公开发布前，私有主包的联合构建与发布预检使用隔离模拟 Pub 仓库；该结果
只证明依赖关系、构建和归档正确，不代表 pub.dev 已发布或审核通过。
