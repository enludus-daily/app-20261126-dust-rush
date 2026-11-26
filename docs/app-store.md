# App Store 提出の準備

> 名前・説明・キーワードなどの正本は `docs/app-store.json`（`.github/workflows/asc.yml` の metadata が App Store Connect に API で入れる）。ここは審査の危険と、本人がすることの記録。

| 項目 | 内容 |
|---|---|
| Bundle ID | com.enludus.daily.019 |
| アプリ名 | すいこみロボ：充電が切れる前に帰れ / Dust Rush: Robot Vacuum（ホーム画面：すいこみロボ / Dust Rush） |
| サポート URL | https://github.com/enludus-daily/app-20261126-dust-rush/issues |
| プライバシーポリシー URL | https://github.com/enludus-daily/app-20261126-dust-rush/blob/main/PRIVACY.md |
| 年齢区分の答え | すべて「なし」の見込み（暴力・恐怖・ギャンブル・成人向け・Web 閲覧・ユーザー生成・生成 AI なし。ほこりは目のあるやさしい絵で、戦いはない）→ 4+。入力は本人 |
| 輸出コンプライアンス | `ITSAppUsesNonExemptEncryption = NO`（標準の暗号だけ。ビルドの答えは asc が NO で入れる） |

## 審査の危険

- 4.3(b) の種類に当たらない理由：懐中電灯・効果音・占いなどではなく、決まり（充電・群れ・強化・落とし物）を持つゲーム。前のアプリ（11/20 灯り島のサバイバー型）とは、戦わずに吸う・帰り道の判断が芯で、視点・見た目・中身が違う
- 既存のアプリとの意味のある違い：Robot Room Cleaner（電池と充電台のシミュレータ）にない、寄ってくる群れ・強化を 3 つから選ぶローグライト・落とし物の賭け・毎日の家
- 長く使える価値（4.2）：30 部屋・6 コース・毎日の家（日付で決まる）・落とし物図鑑 30 種・強化 7 種の組み合わせ
- 他社の名前・商標・見た目を使っていないか：掃除機の商品名・メーカー名・ゲームの名前は使わない。絵はすべて自作の Canvas
- Apple Intelligence：使わない

## 収益の道筋（本人が選ぶ）

- 買い切りの Pro ¥480（`com.enludus.daily.019.pro`、StoreKit 2）。中身・比べた表・勝算は README の「課金」
- 理由：中身が「機能の解放」（部屋・候補・過去の家・見た目・練習）で、あとから増え続けないため。広告は入れない

## App プライバシーの答え（下書き。申告は本人。公開 API がない）

- データの収集：**なし**（根拠：通信しない、解析・広告 SDK なし、保存は端末の UserDefaults だけ）
- トラッキング：なし
- Privacy manifest：`App/Resources/PrivacyInfo.xcprivacy`（UserDefaults: CA92.1）

## スクリーンショット

CI の artifact `screenshots`（iPhone Duo のシミュレータ）。足りない画面は本人と相談。

## 本人がすること

- [ ] App プライバシーを申告する（API がない）
- [ ] 年齢区分を答える
- [ ] TestFlight で動作を確かめる（内部テストのグループ `daily-internal` に自動で配信される）
- [ ] スクリーンショットを確かめる
- [ ] 審査に提出する
