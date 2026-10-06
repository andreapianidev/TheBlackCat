import Foundation

/// What a thought is about. Each topic has hand written lines, used as they are
/// or as a hint for the on device model.
enum ThoughtTopic: Equatable {
    case idle, sleepy, hungry, fed, petted, thrown, scolded, praised, ignoredCall
    case wake, userBack, userGone, night, morning
    case window(owner: String), app(name: String)
    case rain, sun, cold, heat, hotMac, lowBattery, charging
    case meeting(title: String, minutes: Int)
    case music, dog, otherCat, bird, word(String), clap
    case mischief, zoomies, onTop

    /// A plain description of the situation, for the language model prompt.
    var situation: String {
        switch self {
        case .idle: return "non succede niente di speciale"
        case .sleepy: return "hai sonno e cerchi un posto caldo"
        case .hungry: return "hai fame e la ciotola è vuota"
        case .fed: return "ti hanno appena dato da mangiare"
        case .petted: return "il tuo umano ti sta accarezzando"
        case .thrown: return "il tuo umano ti ha appena preso e lanciato giù"
        case .scolded: return "il tuo umano ti ha appena sgridato"
        case .praised: return "il tuo umano ti ha appena fatto un complimento"
        case .ignoredCall: return "il tuo umano ti ha chiamato ma tu fai finta di niente"
        case .wake: return "il Mac si è appena risvegliato e tu con lui"
        case .userBack: return "il tuo umano è appena tornato davanti al Mac"
        case .userGone: return "il tuo umano si è allontanato dal Mac"
        case .night: return "è notte fonda"
        case .morning: return "è mattina presto"
        case .window(let owner): return "sei seduto sopra una finestra di \(owner)"
        case .app(let name): return "il tuo umano ha appena aperto \(name)"
        case .rain: return "fuori piove"
        case .sun: return "fuori c'è il sole"
        case .cold: return "fuori fa freddo"
        case .heat: return "fuori fa caldissimo"
        case .hotMac: return "il Mac sta scottando"
        case .lowBattery: return "la batteria del Mac sta finendo"
        case .charging: return "il Mac è stato appena messo in carica"
        case .meeting(let title, let minutes): return "tra \(minutes) minuti il tuo umano ha l'impegno «\(title)»"
        case .music: return "c'è musica nella stanza"
        case .dog: return "hai sentito o visto un cane"
        case .otherCat: return "hai visto o sentito un altro gatto"
        case .bird: return "sullo schermo c'è un uccellino o un pesce"
        case .word(let w): return "sullo schermo c'è scritto «\(w)»"
        case .clap: return "un rumore forte ti ha spaventato"
        case .mischief: return "hai appena spinto una finestra, per dispetto"
        case .zoomies: return "hai un attacco di energia serale e corri ovunque"
        case .onTop: return "sei salito sul punto più alto dello schermo"
        }
    }
}

enum ThoughtBank {
    static func lines(for topic: ThoughtTopic, name: String) -> [String] {
        switch topic {
        case .idle:
            return ["Sto pensando. Non disturbare.", "Questo desktop è mio, tu lo usi e basta.",
                    "Fisso il vuoto. Il vuoto fissa me.", "Potrei fare qualcosa. Non lo farò.",
                    "Hai notato che sono bellissimo?", "Ho visto qualcosa. Forse.",
                    "Il mio lavoro qui è controllare.", "Silenzio. Sto ascoltando il Mac."]
        case .sleepy:
            return ["Ancora cinque minuti. O cinque ore.", "Le palpebre pesano più di me.",
                    "Cerco un posto caldo. Tipo la tua finestra.", "Dormire è un'arte. Io sono un artista.",
                    "Sbadiglio, quindi esisto."]
        case .hungry:
            return ["La ciotola è vuota. Lo sai, vero?", "Pappa. Adesso. Grazie.",
                    "Sto svenendo. Lentamente. Teatralmente.", "Ti fisso finché non capisci.",
                    "Una crocchetta. Una sola. Poi altre cento.", "Ho fame dal 1987."]
        case .fed:
            return ["Era ora.", "Accettabile.", "Grazie. Non abituarti ai miei grazie.",
                    "Buono. Ora mi serve un pisolino.", "Il servizio migliora."]
        case .petted:
            return ["Sì. Lì. Continua.", "Prrr. Non dirlo a nessuno.", "Va bene, sei perdonato.",
                    "Le tue mani sono quasi degne di me.", "Ancora. Ti ho detto ancora."]
        case .thrown:
            return ["Questo me lo segno.", "Atterraggio perfetto. Rancore anche.",
                    "Non sono un pacco.", "Ti ho visto. Ti ricorderò.", "Dignità intatta. Tu meno."]
        case .scolded:
            return ["Non ho sentito niente.", "Le orecchie sono chiuse per ferie.",
                    "Era già così quando sono arrivato.", "Prove? Non ci sono prove."]
        case .praised:
            return ["Lo so.", "Finalmente qualcuno se ne accorge.", "Mrrp. Grazie, umano.",
                    "Continua pure con i complimenti."]
        case .ignoredCall:
            return ["Ho sentito. Ho deciso di no.", "\(name) non è disponibile in questo momento.",
                    "Forse dopo. Forse mai.", "Chiamami con più rispetto."]
        case .wake:
            return ["Mi sono svegliato prima io.", "Buongiorno. La colazione?", "Stiracchiata d'ordinanza."]
        case .userBack:
            return ["Sei tornato. Non mi eri mancato. Un po'.", "Ah, eccoti. Dov'eri?",
                    "Ti ho tenuto il posto caldo.", "Bentornato, umano."]
        case .userGone:
            return ["Se ne è andato. Il Mac è mio.", "Nessuno guarda. Pisolino.",
                    "Faccio la guardia. Dormendo."]
        case .night:
            return ["La notte è dei gatti.", "Perché sei ancora sveglio?", "Ombra tra le ombre."]
        case .morning:
            return ["Alba. Ora di correre.", "Il sole è sorto. Anche la mia fame."]
        case .window(let owner):
            return ["Questa finestra di \(owner) ora è mia.", "\(owner) è comodo. Resto qui.",
                    "Seduto su \(owner). Non spostarlo.", "Bel panorama da quassù."]
        case .app(let name):
            return appLines(name)
        case .rain:
            return ["Piove. Io non esco.", "Guardo la pioggia. Lei non guarda me.",
                    "Tempo da coperta e pisolino."]
        case .sun:
            return ["C'è il sole. Mi stendo.", "Raggio di sole cercasi.", "Fotosintesi felina in corso."]
        case .cold:
            return ["Fa freddo. Mi arrotolo.", "Mi serve un termosifone. O una tastiera calda."]
        case .heat:
            return ["Troppo caldo per esistere.", "Mi spalmo e non mi muovo più."]
        case .hotMac:
            return ["Questo Mac scotta. Che bello.", "Il Mac è un termosifone. Mi stendo.",
                    "Fa caldo qui. Colpa tua, non mia."]
        case .lowBattery:
            return ["Sta finendo la batteria. Anche la mia pazienza.", "Mettilo in carica. Per me."]
        case .charging:
            return ["Corrente. Calore. Felicità.", "Bene, il Mac mangia. E io?"]
        case .meeting(let title, let minutes):
            return ["Tra \(minutes) minuti: «\(title)». Io dormo.",
                    "Hai «\(title)» tra \(minutes) minuti. Pettinati.",
                    "«\(title)» sta per iniziare. Io resto qui a giudicare."]
        case .music:
            return ["Questa la conosco.", "La coda va a tempo. Il resto no.", "Musica. Approvo."]
        case .dog:
            return ["Cane. Odio.", "Ho sentito un cane. Non è finita qui.", "Un cane? Qui? Mai."]
        case .otherCat:
            return ["Un altro gatto? Io sono l'unico.", "Chi è quello? Rivale.",
                    "Gatto sconosciuto. Lo annuso da lontano."]
        case .bird:
            return ["Uccellino. Uccellino. Uccellino.", "Ek ek ek ek.", "Se fosse vero, sarebbe già mio."]
        case .word(let w):
            return ["Ho letto «\(w)». Mi interessa.", "«\(w)»? Dove?", "Qualcuno ha scritto «\(w)». Arrivo."]
        case .clap:
            return ["Cos'era?!", "Mi è preso un colpo.", "Non si fa. Non si fa così."]
        case .mischief:
            return ["Era lì. Ora no.", "Oops. Non mi dispiace.", "Gravità, ti presento la finestra."]
        case .zoomies:
            return ["NON POSSO FERMARMI.", "Velocità luce!", "Corro e non so perché."]
        case .onTop:
            return ["Il re guarda il suo regno.", "Da quassù siete tutti piccoli."]
        }
    }

    private static func appLines(_ name: String) -> [String] {
        let n = name.lowercased()
        if n.contains("xcode") { return ["Compili ancora?", "Errore alla riga 42. Scherzo.", "Il codice è caldo. Mi siedo sopra."] }
        if n.contains("terminal") || n.contains("iterm") || n.contains("warp") { return ["Scritte che scorrono. Ipnotico.", "Posso premere invio io?"] }
        if n.contains("safari") || n.contains("chrome") || n.contains("firefox") || n.contains("arc") { return ["Cerca \"crocchette\". Fidati.", "Quante schede hai aperto?"] }
        if n.contains("mail") || n.contains("outlook") { return ["Posta. Nessuna è per me.", "Rispondi dopo. Prima accarezzami."] }
        if n.contains("music") || n.contains("spotify") { return ["Metti qualcosa con le fusa.", "La mia playlist: ronron."] }
        if n.contains("facetime") || n.contains("zoom") || n.contains("teams") || n.contains("meet") { return ["Videochiamata? Salgo in inquadratura.", "Saluta da parte mia."] }
        if n.contains("finder") { return ["Cartelle. Tante cartelle.", "Un cestino. Per me?"] }
        if n.contains("whatsapp") || n.contains("messag") || n.contains("telegram") { return ["Scrivi a qualcuno di me.", "Chatti. Io osservo."] }
        if n.contains("photo") || n.contains("foto") { return ["Ci sono foto mie? Dovrebbero."] }
        if n.contains("claude") { return ["Chiedigli di me.", "Lui parla, io faccio le fusa."] }
        return ["Ah, \(name). Interessante. No.", "Apri \(name) e io guardo."]
    }

    /// Makes a model's answer fit a bubble: one short line, house punctuation.
    static func clean(_ raw: String, maxLength: Int = 90) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }
        s = s.replacingOccurrences(of: " \u{2014} ", with: ", ")
            .replacingOccurrences(of: " \u{2013} ", with: ", ")
            .replacingOccurrences(of: "\u{2014}", with: ", ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»*").union(.whitespacesAndNewlines))
        if s.count > maxLength {
            let cut = s.prefix(maxLength)
            if let end = cut.lastIndex(where: { ".!?".contains($0) }) {
                s = String(cut[...end])
            } else if let sp = cut.lastIndex(of: " ") {
                s = String(cut[..<sp]) + "..."
            } else {
                s = String(cut)
            }
        }
        return s.isEmpty ? nil : s
    }
}
