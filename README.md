# DaVinci-Resolve-EXIF_to_Text+
### DaVinci Resolveにおいて画像・動画データのEXIF情報を抽出しテキスト+に出力するスクリプトです。Luaスクリプトを使用しています。

<br>
## 使用方法
Windowsの場合は
>%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts

Macの場合は
>~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts

内の任意のフォルダーにダウンロードしたLuaスクリプトを配置し、DaVinci Resolveを起動する。

DaVinci Resolveでタイムラインに画像クリップを配置し、
>ワークスペース→スクリプト→Exif to Text+

を選択する(エディットページ)。

開いたポップアップウインドウからソース画像が配置されているタイムラインをRead Images Fromで選択、書き出したいExifデータをSelect Metadataで選択。

タイムライン左端の青枠がText+を書き出したいタイムラインに設定されていることを確認して(青枠が表示されてない場合はGenerateボタンを押してみる)Generateボタンを押すと任意のタイムラインにExif情報が記載されたテキスト+が出力される。
<br><br><br>
## 抽出可能なEXIF情報

静止画のカメラ名、レンズ、ISO、シャッタースピード、焦点距離及び動画のメタデータに関してはDaVinci Resolveが読み取ったメタデータに依存している。DaVinci Resolveが読み取れない場合は抽出することができない。
一方、静止画のF値についてはDaVinci Resolveが一般的な静止画絞り値記録位置と違うところを参照していることを踏まえ、バイナリデータを参照しF値を抽出する仕様になっているのでDaVinci Resolveのメタデータとして確認できなくても抽出可能。

<br><br><br>
## 注意事項・免責事項

・挿入されるテキスト+の長さについては DaVinci Resolve → 環境設定 → ユーザー → 編集 内の一般設定、標準ジェネレーターの長さに依存する。**参照元の画像よりデフォルトのテキスト長が長い場合、タイムラインレイアウトが崩れる場合があるので短くしておくことを推奨する**。

・可能な限り多くの画像でEXIF情報を抽出できるようには努めているものの実際にはDaVinci Resolve側で認識できないEXIF情報も多いので読み取れない場合はご容赦願いたい。

・挿入したテキスト+のレイアウトを一括で変更したい場合、以前にリリースしたText-Style-Copyerを使用して欲しい。
ダウンロードはこちらから。　https://github.com/ogizaru/DaVinci-Resolve-Text-Style-Copyer

・**スクリプトの製作にはGoogleのAI、Geminiを多く利用している。生成したコードの安全性検証等には細心の注意を払っているものの、リスクについては理解してご利用頂きたい。**
