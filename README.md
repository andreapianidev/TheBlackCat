# The Black Cat

Un gatto nero che vive sul desktop del Mac. Cammina sopra il Dock, salta sulle
finestre delle altre app, si arrampica sui loro fianchi, ci dorme sopra e cade
se la finestra si chiude. Ha fame, sonno, voglia di giocare, e si ricorda chi
lo ha lanciato.

App macOS nativa (macOS 26 o successivo), solo in italiano per ora. Vive nella
barra dei menu, non ha icona nel Dock.

Pagina del progetto: <https://www.andreapiani.com/the-black-cat.html>

## Compilare

```bash
xcodegen generate
xcodebuild -scheme TheBlackCat -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build.noindex/dd -allowProvisioningUpdates -jobs 3 build
```

Il `.app` esce in `build.noindex/dd/Build/Products/Debug/The Black Cat.app`.

Test (solo logica, non apre nessuna finestra):

```bash
xcodebuild -scheme TheBlackCat -destination 'platform=macOS' -derivedDataPath build.noindex/dd test
```

Numero di build: sale a ogni modifica, nello stesso commit, con
`scripts/bump-build.sh`. Icona: `tools/render-icon.sh` la ridisegna dal rig.
Foglio con tutte le posture: `tools/PoseSheet`.

## Come è fatto

- `Shared/Rig`: il gatto è disegnato in codice, niente immagini. Uno scheletro
  (bacino, torace, testa, quattro zampe a due segmenti con cinematica inversa)
  e una coda fatta di undici molle smorzate che seguono il corpo in ritardo.
  Lo stesso rig disegna l'app, il widget, l'icona e l'icona nella barra.
- `Sources/World`: legge le finestre delle altre app con
  `CGWindowListCopyWindowInfo` (solo i rettangoli, nessun permesso) e ne ricava
  i bordi calpestabili e i fianchi arrampicabili, togliendo i tratti coperti da
  finestre davanti.
- `Sources/Body`: fisica (gravità, salti balistici, arrampicata, lancio) e
  animazione (ciclo del passo, trotto e galoppo, respiro, ammiccare, orecchie).
- `Sources/Brain`: bisogni che salgono e scendono, ritmo del giorno vero
  (pigro a mezzogiorno, scatenato la sera), scelte pesate, obiettivi
  (la ciotola, il puntatore, un posto preferito), reazioni agli eventi.
  I pensieri nel fumetto li scrive Apple Intelligence sul Mac
  (Foundation Models), con frasi scritte a mano quando non c'è.
  Nelle impostazioni, sezione «Cervello», si può scegliere invece Agnes nel
  cloud (`agnes-2.5-flash`, `Sources/Brain/AgnesClient.swift`): se Agnes non
  risponde si torna ad Apple Intelligence, poi alle frasi scritte a mano.
  La chiave sta nel portachiavi del Mac e si importa dal vault
  (`~/.secrets/agnes-ai.env`) o si incolla a mano. Con «Agnes guarda lo
  schermo» un'immagine ridotta dello schermo va ad Agnes ogni due minuti e mezzo
  al massimo.
- `Sources/Senses`: tutto facoltativo, si accende dalle impostazioni.
  - Vista: fotocamera e Vision, ti riconosce davanti al Mac, risponde al saluto.
  - Udito: SoundAnalysis (mani, cani, fischi, musica) e riconoscimento vocale
    in italiano (il suo nome, «giù», «pappa», «nanna», «bravo»).
  - Fotocamera e microfono non restano mai accesi: `Attention` li apre per pochi
    secondi quando torni al Mac, quando clicchi il gatto e, solo la fotocamera,
    ogni tanto per curiosità. Che sei via lo legge da tastiera e mouse
    (e non durante un video, che tiene sveglio lo schermo).
  - Occhi sullo schermo: ScreenCaptureKit e Vision, caccia uccellini e pesci,
    reagisce a parole come «tonno» o «aspirapolvere».
  - Sistema: app in primo piano, risveglio, Mac che scotta, batteria, risparmio
    energetico.
  - Meteo (Open-Meteo, senza chiave), Calendario (EventKit), Notifiche.
  - Dispetti: con Accessibilità sposta di qualche punto la finestra su cui sta.
- `Sources/Voice`: miagolii, fusa e soffi sintetizzati al momento.
- `Widget`: widget per la scrivania con lo stato del gatto e un bottone per la
  pappa. `Shared/CatIntents.swift`: azioni per Comandi rapidi, Siri e Spotlight.

Quello che il gatto vede e sente resta sul Mac e non viene salvato. L'unica
eccezione è Agnes, se la scegli: allora la situazione da cui nasce un pensiero
e, solo se lo attivi, l'immagine ridotta dello schermo vanno ad Agnes.

## Contribuire

Cerchiamo contributor: traduzioni, mantelli, posture, scenette, prove su Mac
diversi. Da dove cominciare e come aprire una pull request: [CONTRIBUTING.md](CONTRIBUTING.md).

## Licenza

MIT, vedi [LICENSE](LICENSE). Il codice si può usare, studiare e modificare
liberamente, citando l'autore.

© 2026 The Black Cat · Andrea Piani · NIE Z2331796-S · Tijarafe, Santa Cruz de Tenerife · Islas Canarias
