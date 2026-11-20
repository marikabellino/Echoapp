const legalVersion = '2026-11-19';

const legalOwner = '[NOME E COGNOME]';
const legalContactEmail = 'mingletheapp1@gmail.com';
const legalMinAge = 18;

typedef LegalSection = ({String title, String body});

const privacySections = <LegalSection>[
  (
    title: 'Chi tratta i tuoi dati',
    body:
        'Il titolare del trattamento è $legalOwner. Per qualsiasi richiesta sulla privacy puoi scrivere a $legalContactEmail.',
  ),
  (
    title: 'Quali dati raccogliamo',
    body:
        '• Dati dell\'account: email, username, nome visualizzato, bio, foto profilo.\n'
        '• Contenuti che pubblichi: drop (foto, testo, luogo, eventuale evento), commenti, like, tag, messaggi in chat, GIF, posizioni o drop che condividi in chat.\n'
        '• Posizione: la posizione del dispositivo, solo mentre usi l\'app, per mostrarti i drop vicini e per creare un drop nel punto in cui ti trovi. Se attivi "Mostra la mia distanza alla cerchia" salviamo una posizione approssimata (circa 1 km) per calcolare le distanze con i tuoi amici; se la disattivi viene cancellata.\n'
        '• Dati tecnici: token per le notifiche push, informazioni necessarie al funzionamento e alla sicurezza del servizio.\n'
        '• Zona casa: se la imposti, la sua posizione resta solo sul tuo telefono e non viene mai inviata a noi. Ai drop lasciati in quella zona salviamo solo l\'indicazione "A casa" e una posizione arrotondata.\n'
        'Dalle foto rimuoviamo i metadati (inclusa la posizione GPS di scatto) prima di caricarle.',
  ),
  (
    title: 'Perché li usiamo e su quale base',
    body:
        '• Fornirti il servizio (account, drop, mappa, cerchia, chat, notifiche): esecuzione del contratto (art. 6.1.b GDPR).\n'
        '• Condividere la tua distanza con la cerchia: consenso (art. 6.1.a), revocabile in ogni momento dalle impostazioni.\n'
        '• Sicurezza, prevenzione di abusi e gestione delle segnalazioni: legittimo interesse (art. 6.1.f) e obblighi di legge (art. 6.1.c), inclusi quelli del Regolamento (UE) 2022/2065 sui servizi digitali.\n'
        'Non vendiamo i tuoi dati e non li usiamo per pubblicità profilata.',
  ),
  (
    title: 'Chi vede cosa',
    body:
        '• Drop pubblici: tutti gli utenti registrati, con il luogo in cui li hai lasciati. Senza account non si vede nulla.\n'
        '• Drop "Cerchia": solo le persone che hai accettato nella tua cerchia.\n'
        '• Drop privati: solo tu. Le foto non hanno un indirizzo pubblico: l\'app le mostra con link temporanei, che scadono, solo a chi ha il permesso di vederle.\n'
        '• Drop lasciati nella zona casa: non sono mai pubblici e sulla mappa non compare il punto esatto.\n'
        '• Chat: solo tu e la persona con cui scrivi.\n'
        '• Distanza: solo gli amici della cerchia, solo se entrambi avete attivato la condivisione, mai la posizione esatta.',
  ),
  (
    title: 'Fornitori che ci aiutano',
    body:
        'Usiamo fornitori che trattano i dati per nostro conto come responsabili del trattamento: Supabase (database, autenticazione, archiviazione foto), Google Firebase (notifiche push), MapTiler (mappe), Klipy (ricerca GIF). Il database, i messaggi e le foto sono conservati su server nell\'Unione Europea (Francoforte, Germania). Alcuni fornitori possono trattare dati anche fuori dall\'Unione Europea: in questi casi il trasferimento avviene sulla base di decisioni di adeguatezza o clausole contrattuali standard della Commissione europea.',
  ),
  (
    title: 'Per quanto tempo',
    body:
        'Conserviamo i dati finché il tuo account è attivo. Se elimini l\'account (Profilo → Impostazioni → Elimina account) cancelliamo profilo, drop, foto, commenti, like e messaggi, salvo quanto dobbiamo conservare per obblighi di legge o per gestire segnalazioni in corso. Le copie di sicurezza tecniche, quando esistono, vengono sovrascritte entro 30 giorni. Le segnalazioni sono conservate per 12 mesi dalla loro chiusura.',
  ),
  (
    title: 'I tuoi diritti',
    body:
        'Puoi chiedere accesso, rettifica, cancellazione, limitazione, portabilità dei tuoi dati e opporti al trattamento, scrivendo a $legalContactEmail. Puoi revocare il consenso in qualsiasi momento. Se ritieni che il trattamento violi la normativa puoi presentare reclamo al Garante per la protezione dei dati personali (www.garanteprivacy.it).',
  ),
  (
    title: 'Età minima',
    body:
        'Mingle è riservata a chi ha almeno $legalMinAge anni. Se scopriamo che un account appartiene a una persona più giovane lo chiudiamo.',
  ),
  (
    title: 'Aggiornamenti',
    body:
        'Versione del $legalVersion. Se cambiamo questa informativa in modo rilevante te lo comunicheremo nell\'app.',
  ),
];

const termsSections = <LegalSection>[
  (
    title: 'Il servizio',
    body:
        'Mingle ti permette di lasciare e scoprire "drop" (foto e testi legati a un luogo), partecipare agli eventi, creare una cerchia di amici e scambiare messaggi. Il servizio è fornito da $legalOwner, a titolo personale.',
  ),
  (
    title: 'Chi può usarlo',
    body:
        'Devi avere almeno $legalMinAge anni e fornire dati veri. Sei responsabile della sicurezza del tuo account e della tua password.',
  ),
  (
    title: 'I tuoi contenuti',
    body:
        'I contenuti che pubblichi restano tuoi. Ci concedi una licenza gratuita, non esclusiva e limitata a mostrarli agli utenti che hai scelto e a far funzionare il servizio. Devi avere i diritti su ciò che pubblichi, incluso il consenso delle persone che compaiono nelle foto.',
  ),
  (
    title: 'Tolleranza zero',
    body:
        'Non è tollerato alcun contenuto o comportamento offensivo, illegale o pericoloso: molestie, bullismo, minacce, incitamento all\'odio, contenuti sessuali o violenti, contenuti che coinvolgono minori, condivisione di dati o posizioni di altre persone senza consenso, spam, truffe, impersonificazione. Vedi le Regole della community.',
  ),
  (
    title: 'Segnalazioni e moderazione',
    body:
        'Puoi segnalare drop, commenti e utenti e bloccare chiunque. Esaminiamo le segnalazioni entro 24 ore e possiamo rimuovere contenuti, limitare o chiudere account. Ti informiamo delle decisioni che ti riguardano e puoi contestarle scrivendo a $legalContactEmail.',
  ),
  (
    title: 'Sicurezza personale',
    body:
        'Mingle mostra luoghi reali. Non lasciare drop pubblici in luoghi che possono identificare la tua abitazione e fai attenzione quando incontri di persona qualcuno conosciuto nell\'app. In caso di pericolo contatta il 112.',
  ),
  (
    title: 'Responsabilità',
    body:
        'Il servizio è fornito "così com\'è". Nei limiti consentiti dalla legge non rispondiamo dei contenuti pubblicati dagli utenti. Restano salvi i diritti che ti riconosce la legge come consumatore.',
  ),
  (
    title: 'Chiusura dell\'account',
    body:
        'Puoi eliminare l\'account in qualsiasi momento da Profilo → Impostazioni → Elimina account. Possiamo sospendere o chiudere gli account che violano questi termini.',
  ),
  (
    title: 'Legge applicabile',
    body:
        'Si applica la legge italiana. Per i consumatori è competente il foro del luogo di residenza. Versione del $legalVersion.',
  ),
];

const guidelinesSections = <LegalSection>[
  (
    title: 'Rispetta le persone',
    body:
        'Niente insulti, molestie, minacce, discriminazioni o contenuti che umiliano qualcuno.',
  ),
  (
    title: 'Rispetta la privacy',
    body:
        'Non pubblicare foto di altre persone senza il loro consenso. Non condividere indirizzi, posizioni o dati personali di altri. Non taggare qualcuno in contenuti che potrebbero metterlo a disagio.',
  ),
  (
    title: 'Proteggi te stesso',
    body:
        'Evita drop pubblici a casa tua o in posti che frequenti ogni giorno: usa la visibilità "Cerchia" o "Privato". Condividi la tua posizione in chat solo con persone di cui ti fidi.',
  ),
  (
    title: 'Niente contenuti vietati',
    body:
        'Vietati contenuti sessuali espliciti, violenza, droghe, armi, contenuti illegali e qualsiasi contenuto che coinvolga minori.',
  ),
  (
    title: 'Segnala e blocca',
    body:
        'Se qualcosa non va, usa "Segnala" su drop, commenti e profili, oppure "Blocca": la persona bloccata non potrà più vederti né scriverti. Le segnalazioni sono anonime per chi viene segnalato.',
  ),
];
