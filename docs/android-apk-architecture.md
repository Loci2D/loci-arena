# Arquitetura Mobile (Android APK) e Pipeline CI/CD

Este documento consolida o planejamento técnico e o fluxo definitivo de build/distribuição do cliente **Loci Arena** para Android (`.apk`), cobrindo os cards **#95 (`i12f4Rdr`)**, **#94 (`QESR896r`)** e **#98 (`ubntLOwL`)** e as issues [`Loci2D/loci-arena#71`](https://github.com/Loci2D/loci-arena/issues/71) e [`Loci2D/sdk-love2d#15`](https://github.com/Loci2D/sdk-love2d/issues/15).

---

## 1. Base de Rede e Versões (`loci2d v0.6.5-rev.5` + `sdk-love2d v0.6.4`)

* **Engine (`loci2d v0.6.5-rev.5`):** adiciona `session_token` em `JoinIntent`/`ServerResponse` e `SessionState::GracePeriod` (30s padrão via `SESSION_GRACE_PERIOD_SECS`), preservando `entity_id`, posição, time e KDA durante reconexões.
* **SDK (`sdk-love2d v0.6.4`):** adiciona `loci.resume(...)`, `loci.get_session_token()`, `loci.set_session_token()` e envio automático do `session_token` no watchdog de reconexão — essencial para tolerar trocas Wi-Fi ↔ 4G, rebinding de NAT e pausa/retorno do app no Android sem spawnar clones.

---

## 2. Dependência Nativa Android (`lua-protobuf` / `libpb.so`)

Todo o código Lua do jogo (`client/`) e do SDK (`loci_client.lua`, `loci/*.lua`, `protoc.lua`, `game_packets.proto`) é multiplataforma e roda dentro de `game.love` (inclusive `luasocket`, que já vem embutido no runtime do Love2D Android, e `game_packets.proto`, lido via `love.filesystem.read()` em `loci/network/schema.lua`).

O único componente C nativo é o `lua-protobuf` (`lib/src/pb.c`):
* No Android, o `dlopen()` não consegue carregar bibliotecas `.so` empacotadas dentro do `.love` (arquivo ZIP). Elas precisam existir como `libpb.so` em `jniLibs/<abi>/` do APK.
* **Estratégia adotada:** o `sdk-love2d` não precisa manter cross-compilação Android em seu próprio CI; ele apenas inclui `lib/src/` no bundle de release e garante suporte a `lib?.so` no `package.cpath` quando `love.system.getOS() == "Android"` (`Loci2D/sdk-love2d#15`).
* O workflow do `loci-arena` compila `pb.c` diretamente junto com o `love2d/love-android` (`11.5a`) como módulo de terceiros em `love/src/jni/lua-modules/libpb/` usando [`android/lua-modules/libpb/Android.mk`](../android/lua-modules/libpb/Android.mk), linkando contra `liblove` (`LuaJIT-2.1`) para as ABIs `arm64-v8a` e `armeabi-v7a`.

---

## 3. Empacotamento do `game.love`

O script [`scripts/package_love.sh`](../scripts/package_love.sh) gera um arquivo `.love` limpo a partir de `client/`:
* Desreferencia links simbólicos (`client/loci2d` -> `../sdk-love2d`) em diretório temporário.
* Remove binários desktop (`*.so`, `*.dll`, `*.dylib`), backups (`loci2d.bak`), `docs/`, `examples/`, `logs/` e `test_sdk.lua`.
* Compacta `main.lua`, `conf.lua`, `assets/`, `src/` e `loci2d/` na raiz de `dist/game.love`.

Uso local:
```bash
./scripts/package_love.sh
```

---

## 4. Pipeline CI/CD do APK (`.github/workflows/build-android.yml`)

### Gatilhos e Modos de Build
* **`workflow_dispatch`:** build manual sob demanda (`build_type`: `debug` ou `release`), publicando o `.apk` e `SHA256SUMS.txt` como Artifact (retenção de 14 dias).
* **`push` em tags `v*`:** build `release` assinado e publicação automática no **GitHub Releases**.

### Etapas do Workflow
1. Configura `ubuntu-latest` com JDK 17 (`temurin`), Android SDK e NDK `25.2.9519653` + `build-tools;34.0.0`.
2. Baixa o SDK via `./scripts/setup_sdk.sh --download` (com fallback para baixar `pb.c`/`pb.h` da tag correspondente em `Loci2D/sdk-love2d` caso o bundle ainda não inclua `lib/src/`).
3. Gera `dist/game.love` com `./scripts/package_love.sh`.
4. Clona `love2d/love-android` na tag `11.5a` (com submódulos).
5. Injeta:
   * `dist/game.love` → `love-android/app/src/embed/assets/game.love`
   * `android/lua-modules/libpb/Android.mk` + `pb.c`/`pb.h` → `love-android/love/src/jni/lua-modules/libpb/`
   * Metadados em `gradle.properties`: `app.name=Loci Arena`, `app.application_id=org.loci2d.arena`, `app.orientation=sensorLandscape`, `app.version_code=${{ github.run_number }}` e `app.version_name`.
6. Compila `./gradlew assembleEmbedNoRecordDebug` (debug) ou `./gradlew assembleEmbedNoRecordRelease` (release).
7. Em builds `release`, alinha com `zipalign` e assina/verifica com `apksigner`.

### Configuração de Assinatura (GitHub Secrets)
Para gerar releases assinadas (`tags: v*` ou `build_type: release`), configure os 4 secrets no repositório (`Settings -> Secrets and variables -> Actions`):

| Secret | Descrição |
| :--- | :--- |
| `ANDROID_KEYSTORE_BASE64` | Arquivo `.jks` codificado em base64 (`base64 -w 0 release.jks`) |
| `ANDROID_KEYSTORE_PASS` | Senha da keystore (`storepass`) |
| `ANDROID_KEY_ALIAS` | Alias da chave dentro da keystore |
| `ANDROID_KEY_PASS` | Senha da chave (`keypass`) |

Exemplo para gerar uma keystore nova localmente:
```bash
keytool -genkey -v -keystore loci-arena-release.jks -alias loci-arena \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -w 0 loci-arena-release.jks
```

---

## 5. Adaptação Mobile e Fluxo de Conexão (`#95` / `#98`)

### Preservação do Fluxo Desktop
* [`client/conf.lua`](../client/conf.lua) ativa `fullscreen` e `highdpi` automaticamente quando `love._os` é `Android` ou `iOS`, mantendo janela `1280x720` (`minwidth=800`, `minheight=600`) no desktop.
* [`client/main.lua`](../client/main.lua) inicializa `push:setupScreen` com `love.graphics.getDimensions()` reais.
* Quando a tela de conexão (`#98 ubntLOwL`) for implementada, o `love.load` deve manter **fast-path no desktop** (se `os ~= "Android"` e `os ~= "iOS"`, pular a tela de conexão por padrão e conectar direto em `LOCI_SERVER_IP` / `127.0.0.1`, abrindo a UI apenas com `LOCI_CONNECT_UI=1` ou `--connect-ui`).

### UX Mobile Planejada (`#98 ubntLOwL`)
* **Tela de Conexão:** campos de IP/Host, Porta e Nickname, presets (`10.3.17.201`, `192.168.0.2`, `127.0.0.1`), teclado virtual via `love.keyboard.setTextInput(true)`, persistência via `love.filesystem` (`t.identity = "loci-arena"`) e botão **"Retomar Sessão"** usando `loci.resume()` com `session_token`.
* **Paridade Touch:** barra superior compacta (fora das zonas de joystick e skills, respeitando `love.window.getSafeArea()`) com botões táteis para `Trocar Herói` (`K`), `Placar KDA` (`Tab` em modo toggle), `Som/Mudo` (`M`) e `Sair/Config`.
