# The Black Cat, ripartenza in una nuova sessione

Lavoriamo su **The Black Cat**, un'app macOS nativa: un gatto che vive sul
desktop. Cammina sopra il Dock, salta sulle finestre delle altre app, si
arrampica sui loro fianchi, scivola, cade, dorme, mangia, gioca col mouse,
reagisce ai sensi del Mac. Ogni tanto arriva un ospite (scenette).
Solo in italiano per ora. Il gatto realistico nero è il preferito di Andrea:
la grafica di base non va stravolta.

## Dove sta tutto

- Progetto: `~/prototipi/TheBlackCat`
- Repository: `andreapianidev/TheBlackCat`, **privato** (verifica con
  `gh api repos/andreapianidev/TheBlackCat --jq .private` prima di ogni push)
- App installata: `/Applications/The Black Cat.app` (build Release)
- Memoria del gatto: `~/Library/Application Support/TheBlackCat/cat.json`
- Impostazioni: `defaults read app.andreapiani.theblackcat`
- Dati condivisi con il widget: App Group `ERAK83QBBM.app.andreapiani.theblackcat`
- Chiave Agnes: nel vault `~/.secrets/agnes-ai.env` (`AGNES_API_KEY`), copiata
  dall'app nel portachiavi (service `app.andreapiani.theblackcat`, account
  `agnes`) solo quando in Impostazioni si preme "Importa la chiave dal vault".
  Mai nel repository, mai stampata nel terminale.
- Chiave DeepSeek: nel vault `~/.secrets/deepseek-harness.env` (`DEEPSEEK_API_KEY`,
  modello `deepseek-v4-flash`), copiata nel portachiavi (stesso service, account
  `deepseek`) quando in Impostazioni si sceglie DeepSeek o si preme "Importa".
- Stato attuale: versione 1.0, **build 9**. Il numero è visibile nel menu del gatto
  nella barra dei menu.

## Struttura del codice

- `project.yml`: progetto xcodegen. Tre bersagli: `TheBlackCat` (app),
  `TheBlackCatWidget` (widget, sandbox, App Group), `TheBlackCatTests`
  (solo logica pura). macOS 26 minimo, Swift 5 mode, team ERAK83QBBM.
- `Shared/Rig/`: il gatto disegnato in codice, niente immagini.
  `CatPose.swift` (posture, 20 tipi, e stili della coda), `CatRig.swift`
  (disegno: zampe a cinematica inversa, mantelli, segni, stile fumetto,
  contorno senza sfocatura), `TailChain.swift` (coda a molle),
  `CatCoat.swift` (9 mantelli: nero, smoking, Silvestro, rosso tigrato,
  certosino, bianco, siamese, tricolore, soriano), `CatMotion.swift` (gesti:
  lavaggio del muso, rotolata, starnuto, sogni).
- `Shared/SharedStore.swift`, `Shared/CatIntents.swift`: comandi tra widget,
  Comandi rapidi e app (notifica Darwin), istantanea per il widget.
- `Sources/World/`: `WindowScanner` (finestre con CGWindowList, solo
  rettangoli; include le miniature di Stage Manager), `WorldModel`
  (bordi calpestabili e fianchi arrampicabili, con occlusione), `Geometry`.
- `Sources/Body/`: `CatBody` (fisica: a terra, in volo, arrampicata, appeso
  a un bordo, trascinato), `Animator` (passo, respiro, occhi, coda),
  `Ballistics` (salti).
- `Sources/Brain/`: `Brain` (bisogni, scelte pesate, compiti, reazioni,
  API per le scenette), `Navigator` (salti e arrampicate possibili),
  `Needs`, `ThoughtText` (frasi scritte a mano), `ThoughtEngine` (pensieri
  con Apple Intelligence, DeepSeek o Agnes), `Mind` (il carattere: ogni 1-2
  minuti decide cosa fare, `CatIntent`, con un diario; Apple Intelligence con
  generazione guidata `@Generable`, nel cloud JSON), `AgnesClient` (anche
  `VaultKey`, le chiavi nel portachiavi), `DeepSeekClient` (`deepseek-v4-flash`,
  `thinking` disattivato, e `CloudBrain`), `Fly` (la mosca).
- `Sources/Scenes/`: `Visitors.swift` (uccellino, cane, topolino, gomitolo,
  farfalla, scatola, robot aspirapolvere, gatto rivale, puntino laser, ragnetto,
  foglia, lucciole), `SceneDirector.swift` (copioni delle scenette: la prima
  45-90 secondi dopo l'avvio, poi una ogni 3-6 minuti, da un mazzo mescolato).
- `Sources/Senses/`: `Attention` (apre fotocamera e microfono solo per pochi
  secondi: ritorno al Mac, clic sul gatto, curiosità; assenza da tastiera e
  mouse, non durante un video), vista (fotocamera + Vision), udito
  (SoundAnalysis + riconoscimento vocale in italiano),
  occhi sullo schermo (ScreenCaptureKit + Vision, e Agnes se attivato),
  sistema (app in primo piano, calore, batteria), meteo (Open-Meteo),
  calendario, notifiche, `WindowNudger` (dispetti con Accessibilità:
  spinge o, raramente, riduce a icona; non chiude mai).
- `Sources/Voice/CatVoice.swift`: miagolii, fusa, soffi, abbaio, cinguettii,
  squittii sintetizzati al momento.
- `Sources/UI/`: pannello trasparente del gatto e particelle, fumetto
  (Liquid Glass o a fumetto), ciotola, menu nella barra, impostazioni.
- `Sources/App/CatController.swift`: il ciclo a fotogrammi, i sensi, il mondo,
  il regista delle scenette, il menu.
- `tools/`: `render-icon.sh` (icona dal rig), `PoseSheet` (foglio di prova
  di posture e mantelli, per controllare i disegni senza avviare l'app).
- `scripts/bump-build.sh`: alza il numero di build e rigenera il progetto.

## Comandi

```bash
cd ~/prototipi/TheBlackCat
./scripts/bump-build.sh                       # a ogni modifica, nello stesso commit
xcodebuild -project TheBlackCat.xcodeproj -scheme TheBlackCat -destination 'platform=macOS' \
  -derivedDataPath build/dd -allowProvisioningUpdates -jobs 3 test -only-testing:TheBlackCatTests
xcodebuild -project TheBlackCat.xcodeproj -scheme TheBlackCat -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/dd -allowProvisioningUpdates -jobs 3 build
# installare e riavviare (Andrea lo chiede dopo ogni modifica)
pkill -f "The Black Cat.app/Contents/MacOS"; sleep 1
rm -rf "/Applications/The Black Cat.app"
ditto "build/dd/Build/Products/Release/The Black Cat.app" "/Applications/The Black Cat.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/The Black Cat.app"
open "/Applications/The Black Cat.app"
```

Foglio di prova delle posture:
`swiftc -O Shared/Rig/*.swift tools/PoseSheet/main.swift -o build/pose-sheet && build/pose-sheet /tmp/pose.png coats`

## Regole di lavoro

- Andrea collauda, tu compili, misuri e installi. Dopo ogni modifica:
  build, test, numero di build alzato, Release in `/Applications`, riavvio,
  commit e push (repo privato, niente segreti nel diff).
- Testi visibili in italiano, mai la lineetta lunga né quella media.
- Riga legale: `© 2026 The Black Cat · Andrea Piani · NIE Z2331796-S · Tijarafe, Santa Cruz de Tenerife · Islas Canarias`. Mai "Immaginet".
- Cloud: DeepSeek (`deepseek-v4-flash`, chiave di `deepseek-harness.env`, la stessa
  della Bottega) o Agnes; Apple Intelligence sul Mac. Andrea ha chiesto DeepSeek
  il 06/10/2026. Chiavi solo nel portachiavi, mai nel repository.
- "Silvestro" è un personaggio Warner Bros: va bene per uso personale, ma se il
  repository diventa pubblico o l'app si distribuisce va rinominato.
- Mac: MacBook Air M2 16 GB, schermo 1710 x 1107 punti, Stage Manager attivo.
  Niente simulatori. Al massimo due build in parallelo.
- Prima di dire "funziona" misura: CPU con `ps -o %cpu= -p $(pgrep -f "The Black Cat.app/Contents/MacOS")`,
  posizione della finestra del gatto con CGWindowList, punti caldi con `sample`.

## Cose già imparate (non rifarle)

- Il ciclo a fotogrammi va legato allo schermo, non alla finestra del gatto:
  una finestra fuori dallo schermo ferma il suo display link e il gatto resta
  congelato. C'è anche un controllo ogni secondo e il recupero sul pavimento.
- CPU: circa 6-8% normale, picchi del 16% in corsa. Pesavano il sonno a 60 fps,
  il testo delle particelle ricomposto a ogni fotogramma e l'alone sfocato.
  Disegnare in una bitmap propria e passarla al layer costa DI PIU' (25-30%):
  provato e tolto.
- Agnes `agnes-2.5-flash` ragiona prima di rispondere: senza
  `chat_template_kwargs.enable_thinking=false` restituisce testo vuoto.
- Le miniature di Stage Manager sono alte circa 139 punti: i fianchi
  arrampicabili partono da 90.

## Non ancora verificato dal vivo

- Il carattere con DeepSeek: decisioni coerenti, pensieri nel fumetto.
- Le scenette nuove (ragnetto, foglia, lucciole) e i gesti spontanei nuovi.
- Fotocamera e microfono che si accendono solo per pochi secondi.

- Le scenette in movimento (robot su cui salire, gatto dentro la scatola,
  fuga dal cane).
- Agnes dentro l'app: importazione della chiave, pensieri, JSON quando guarda
  lo schermo.
- Riduci a icona con i Dispetti, comandi vocali con il nuovo filtro sul parlato.

## Idee aperte

- CPU ancora piu' bassa (livelli Core Animation al posto del ridisegno).
- Lo stesso gatto su piu' Mac con iCloud (serve la capability nell'account).
- Inglese, poi distribuzione: firma Developer ID e notarizzazione, oppure
  Mac App Store (servirebbe la sandbox).

Inizia leggendo `README.md` e questo file, poi chiedi ad Andrea cosa ha visto
nell'ultimo collaudo.
