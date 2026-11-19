# InkKey · 水墨双语九宫格输入法

iPhone 上的九宫格（T9）中英文输入法，打字时上行中文、下行英文对照，点哪行上哪行；
每个候选都带小喇叭，点一下朗读英文并自动收进**生词本**。整体水墨风，支持换字体。

- 主 App `com.lin.inkkey`（SwiftUI，iOS 17+）：启用引导、生词本、设置
- 键盘扩展 `com.lin.inkkey.keyboard`：九宫格键盘 + 双语候选栏
- App Group：`group.com.lin.inkkey`（设置、生词本、自定义字体共享）

## 键盘布局

```
，  [1 @#] [2 ABC] [3 DEF]        ⌫
。  [4 GHI] [5 JKL] [6 MNO]       重输
？  [7 PQRS][8 TUV][9 WXYZ]       换行
！  [符号]  [123]   [ 空格 ]  [中/英] [🌐]
```

- 左列标点：中文 `，。？！`，英文自动变 `, . ? !`
- 退格：轻点删一格，按住连续删
- 重输：清空当前九宫格输入的拼音/数字
- 换行：高键，跨两行高度
- `1 / @#` 打开符号页，`123` 数字页，`中/英` 切换中英文 T9

## 双语候选栏

每个候选是一对：

| 模式 | 上行（点它上屏） | 下行（点它上屏） |
| --- | --- | --- |
| 中文 | 中文词（上方小字是拼音） | 英文释义（点它插入英文） |
| English | 英文词（上方小字是 IPA） | 中文释义（点它插入中文） |

行尾 🔊：朗读英文，并把这词写进生词本（App Group 共享）。

## 换字体

设置 → 键盘字体：

1. 内置四套：系统默认、水墨宋体、楷体手写、圆润黑体、等宽极客（按系统实际提供的字体自动回退）
2. 导入自定义字体：点「导入」选 `.ttf` / `.otf` / `.ttc`，文件复制进
   `App Group/Fonts/`，用 `CTFontManagerRegisterFontsForURL(..., .process, nil)`
   在主 App 与键盘扩展里同时注册，按键、候选词、双语对照行全部生效
3. 字体读不出来时自动退回系统字体，不会白屏或闪退

## 离线词库

`Resources/dictionary.json`（约 1.5 MB）：

- 中文 14,501 条：3,600 个高频汉字 + 10,901 个 2–4 字词，带拼音、英文释义、词频
- 英文 9,000 词：带 IPA、简明中文释义、频率排名
- T9 匹配：拼音/单词字母 → 数字序列前缀匹配；另建「声母首字母」索引，
  打 `96` 能出「我们」（w+m）；按「长度差 → 词频」排序，精确打满的优先
- 词库在后台队列解析，键盘首屏不卡；文件小，扩展内存占用远低于 48 MB 限制

数据来源（构建时脚本 `Tools/build_dictionary.py` 生成，运行时不联网）：

| 数据 | 来源 | 许可 |
| --- | --- | --- |
| 中英词条与拼音 | [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict) | CC BY-SA 4.0 |
| 中文词频 | [jieba](https://github.com/fxsjy/jieba) `dict.txt` | MIT |
| 英文词表 | [google-10000-english](https://github.com/first20hours/google-10000-english) | Apache-2.0 |
| 英式/美式音标 | [ipa-dict](https://github.com/open-dict-data/ipa-dict) | MIT |
| 英中释义 | [ECDICT](https://github.com/skywind3000/ECDICT) | MIT |

重新生成：

```sh
sh Tools/fetch_data.sh          # 下载原始数据到 Tools/_data（约 80 MB，不进仓库）
python3 Tools/build_dictionary.py
python3 Tools/make_icon.py      # 重新画 1024 AppIcon
```

## 构建

```sh
brew install xcodegen
xcodegen generate
open InkKey.xcodeproj
```

或直接用 GitHub Actions：`.github/workflows/build-ipa.yml`（未签名 IPA，产物在 Release）。
本仓库不跟踪该 workflow 文件（本地通过 `.git/info/exclude` 排除），
需要自己贴到 GitHub 网页端新建文件里（token 没有 workflows 权限）。

## 安装与启用

1. 用 全能签 / AltStore / SideStore 等自签安装 `InkKey-unsigned.ipa`
2. **重签时勾上 App Group `group.com.lin.inkkey`**，否则键盘读不到主 App 的设置
3. 设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → InkKey
4. 点开 InkKey → 打开「允许完全访问」（发音、生词本、字体共享、自定义字体读取都需要）
5. 任意输入框长按地球键切到 InkKey

## 版本

`MARKETING_VERSION 1.0.0` / `CURRENT_PROJECT_VERSION 1`，主 App 与扩展的 `project.yml`
里都显式设置，避免全能签重签时报「版本号缺失」。
