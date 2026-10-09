# Contribuire a The Black Cat

Grazie di voler dare una zampa. The Black Cat è un'app macOS open source
(licenza MIT): un gatto nero disegnato in codice che vive sul desktop.
Cerchiamo contributor di ogni tipo, non solo chi scrive Swift.

Pagina del progetto: <https://www.andreapiani.com/the-black-cat.html>

## Da dove cominciare

Lavori aperti, dal più semplice:

- **Provarlo su Mac diversi.** Più monitor, Stage Manager, Spaces, schermi
  enormi. Apri una issue con quello che succede, meglio se con un video.
- **Un mantello nuovo.** Un mantello è una manciata di colori e qualche
  macchia in `Shared/Rig/CatCoat.swift`. Manca, per esempio, il tartarugato.
- **Insegnargli l'inglese.** Oggi parla solo italiano. Servono le stringhe
  in un String Catalog e le frasi del gatto (`Sources/Brain/ThoughtText.swift`)
  in inglese, con lo stesso carattere.
- **Una postura in più.** Le posture sono in `Shared/Rig/CatPose.swift`; il
  foglio con tutte le posture si genera con `tools/PoseSheet`.
- **Un ospite nuovo.** Le scenette (il ragnetto, la foglia, le lucciole)
  stanno in `Sources/Scenes`.
- **Scaricarlo senza Xcode.** Una GitHub Action che compili, firmi e
  notarizzi una release.

Hai un'idea diversa? Apri prima una issue, così ne parliamo.

## Compilare

Serve macOS 26, Xcode 26 e XcodeGen.

```bash
gh repo fork andreapianidev/TheBlackCat --clone
cd TheBlackCat
brew install xcodegen
xcodegen generate
open TheBlackCat.xcodeproj
```

Per firmare l'app sul tuo Mac metti il tuo team di sviluppo in `project.yml`,
alla voce `DEVELOPMENT_TEAM`, e non includere quella modifica nella pull
request.

## La pull request

1. Lavora su un ramo con un nome che dica cosa fa (`mantello-tartarugato`).
2. Tieni la modifica piccola: una cosa per pull request.
3. Se cambia qualcosa che si vede, allega un video o una gif del gatto.
4. Il numero di build sale a ogni modifica all'app, nello stesso commit:
   usa `scripts/bump-build.sh`, non modificare il progetto a mano.
5. Niente chiavi, token o password nei commit. Le chiavi dei modelli nel
   cloud vivono solo nel portachiavi del Mac.

## Lo stile

- Il gatto nero realistico è la grafica di base: si aggiunge, non si stravolge.
- Il rig in `Shared/Rig` si compila da solo, senza AppKit: usalo per provare
  posture e mantelli senza avviare l'app.
- I testi dell'app sono in italiano semplice, frasi brevi.

Contribuendo accetti che il tuo codice sia distribuito con la licenza MIT
del progetto.
