defmodule ExBlogWeb.LegalCopy do
  @moduledoc false

  @site_name "spectre.elchemista.com"
  @site_domain "spectre.elchemista.com"
  @contact_email "elchemista@gmail.com"

  @spec site_name() :: String.t()
  def site_name, do: @site_name

  @spec site_domain() :: String.t()
  def site_domain, do: @site_domain

  @spec contact_email() :: String.t()
  def contact_email, do: @contact_email

  @spec cookie_policy(String.t()) :: map()
  def cookie_policy("it") do
    %{
      kind: :cookie,
      id: "cookie-policy",
      file: "legal/cookies-policy.md",
      eyebrow: "controlli privacy",
      title: "Cookie Policy",
      summary:
        "Questa informativa spiega quali cookie e tecnologie locali usa spectre.elchemista.com, perché vengono usati e come puoi cambiare scelta in qualsiasi momento.",
      updated: "4 agosto 2026",
      sections: [
        %{
          id: "cosa-sono",
          title: "1. Cosa sono i cookie",
          paragraphs: [
            "I cookie sono piccoli file di testo salvati dal browser quando visiti un sito. Possono essere necessari per il funzionamento tecnico, ricordare una preferenza oppure, solo con il tuo consenso, misurare l'utilizzo del servizio."
          ],
          items: [],
          links: []
        },
        %{
          id: "come-li-usiamo",
          title: "2. Come li usiamo",
          paragraphs: [
            "spectre.elchemista.com utilizza il minimo indispensabile per servire le pagine, proteggere le aree riservate e ricordare le tue scelte."
          ],
          items: [
            %{
              title: "Consenso cookie",
              body:
                "Il cookie spectre_cookie_consent registra le categorie accettate o rifiutate, così il banner non viene riproposto a ogni pagina."
            },
            %{
              title: "Sessione e sicurezza",
              body:
                "Phoenix può usare cookie tecnici firmati e token CSRF quando una funzione richiede una sessione, per esempio nelle aree amministrative. Non sono usati per profilazione."
            },
            %{
              title: "Preferenza grafica",
              body:
                "La scelta del tema chiaro o scuro viene conservata nel localStorage del browser, non in un cookie, e resta solo sul dispositivo."
            },
            %{
              title: "Analisi facoltativa",
              body:
                "La categoria analytics resta disattivata finché non acconsenti. Al momento il bundle pubblico non carica servizi analitici o pubblicitari di terze parti."
            }
          ],
          links: []
        },
        %{
          id: "terze-parti",
          title: "3. Cookie di terze parti",
          paragraphs: [
            "Il sito non installa intenzionalmente cookie pubblicitari di terze parti. I siti esterni raggiunti tramite link applicano informative e preferenze proprie, sulle quali spectre.elchemista.com non ha controllo.",
            "Se in futuro venissero aggiunti strumenti analitici non essenziali, saranno bloccati fino al consenso e questa informativa verrà aggiornata prima dell'attivazione."
          ],
          items: [],
          links: []
        },
        %{
          id: "scelte",
          title: "4. Le tue scelte",
          paragraphs: [
            "Dal banner puoi accettare tutto, mantenere solo i cookie necessari oppure aprire le preferenze. Puoi riaprire lo stesso pannello in qualsiasi momento dal link “preferenze cookie” nel footer.",
            "La revoca vale per i trattamenti futuri. Puoi inoltre eliminare i cookie già presenti usando le impostazioni del browser. Alcune funzioni protette potrebbero non operare correttamente se blocchi i cookie tecnici."
          ],
          items: [],
          links: [
            %{
              label: "Gestire i cookie in Chrome",
              href: "https://support.google.com/chrome/answer/95647"
            },
            %{
              label: "Gestire cookie e dati in Firefox",
              href: "https://support.mozilla.org/kb/clear-cookies-and-site-data-firefox"
            },
            %{
              label: "Gestire cookie e dati in Safari",
              href:
                "https://support.apple.com/guide/safari/manage-cookies-and-website-data-sfri11471/mac"
            }
          ]
        },
        %{
          id: "base-giuridica",
          title: "5. Base giuridica e consenso GDPR",
          paragraphs: [
            "I cookie strettamente necessari sono trattati per il legittimo interesse a fornire un sito funzionante e sicuro, ai sensi dell'articolo 6, paragrafo 1, lettera f) del GDPR.",
            "Ogni cookie non essenziale richiede invece il consenso preventivo ai sensi dell'articolo 6, paragrafo 1, lettera a). Il consenso è facoltativo e può essere revocato con la stessa facilità con cui viene prestato."
          ],
          items: [],
          links: []
        },
        %{
          id: "durata",
          title: "6. Durata",
          paragraphs: [
            "La preferenza spectre_cookie_consent dura fino a 182 giorni, salvo cancellazione anticipata dal browser. I cookie tecnici di sessione scadono al termine della sessione o secondo il periodo strettamente necessario alla funzione richiesta."
          ],
          items: [],
          links: []
        },
        %{
          id: "modifiche",
          title: "7. Modifiche a questa informativa",
          paragraphs: [
            "Questa Cookie Policy può essere aggiornata quando cambiano le tecnologie utilizzate o gli obblighi normativi. La data riportata in alto indica l'ultima revisione; le modifiche hanno effetto dalla pubblicazione su questa pagina."
          ],
          items: [],
          links: []
        }
      ]
    }
  end

  def cookie_policy("en") do
    %{
      kind: :cookie,
      id: "cookie-policy",
      file: "legal/cookies-policy.md",
      eyebrow: "privacy controls",
      title: "Cookie Policy",
      summary:
        "This notice explains which cookies and local technologies spectre.elchemista.com uses, why they are used, and how you can change your choice at any time.",
      updated: "August 4, 2026",
      sections: [
        %{
          id: "what-are-cookies",
          title: "1. What cookies are",
          paragraphs: [
            "Cookies are small text files stored by your browser when you visit a website. They may be required for technical operation, remember a preference, or—only with your consent—measure use of the service."
          ],
          items: [],
          links: []
        },
        %{
          id: "how-we-use-them",
          title: "2. How we use them",
          paragraphs: [
            "spectre.elchemista.com uses only what is needed to serve pages, protect restricted areas, and remember your choices."
          ],
          items: [
            %{
              title: "Cookie consent",
              body:
                "The spectre_cookie_consent cookie records the categories you accepted or rejected so that the banner is not shown on every page."
            },
            %{
              title: "Session and security",
              body:
                "Phoenix may use signed technical cookies and CSRF tokens when a feature requires a session, for example in administrative areas. They are not used for profiling."
            },
            %{
              title: "Display preference",
              body:
                "The light or dark theme choice is kept in browser localStorage, not in a cookie, and remains on your device."
            },
            %{
              title: "Optional analytics",
              body:
                "The analytics category stays disabled until you consent. The current public bundle does not load third-party analytics or advertising services."
            }
          ],
          links: []
        },
        %{
          id: "third-parties",
          title: "3. Third-party cookies",
          paragraphs: [
            "The site does not intentionally install third-party advertising cookies. External websites reached through links apply their own notices and preferences, which spectre.elchemista.com does not control.",
            "If non-essential analytics tools are added in the future, they will remain blocked until consent and this notice will be updated before activation."
          ],
          items: [],
          links: []
        },
        %{
          id: "choices",
          title: "4. Your choices",
          paragraphs: [
            "From the banner you can accept all categories, keep only necessary cookies, or open detailed preferences. You can reopen the same panel at any time through the “cookie preferences” control in the footer.",
            "Withdrawal applies to future processing. You may also delete existing cookies through your browser settings. Some restricted features may not work correctly if technical cookies are blocked."
          ],
          items: [],
          links: [
            %{
              label: "Manage cookies in Chrome",
              href: "https://support.google.com/chrome/answer/95647"
            },
            %{
              label: "Clear cookies and site data in Firefox",
              href: "https://support.mozilla.org/kb/clear-cookies-and-site-data-firefox"
            },
            %{
              label: "Manage cookies and website data in Safari",
              href:
                "https://support.apple.com/guide/safari/manage-cookies-and-website-data-sfri11471/mac"
            }
          ]
        },
        %{
          id: "legal-basis",
          title: "5. Legal basis and GDPR consent",
          paragraphs: [
            "Strictly necessary cookies are processed for the legitimate interest of providing a functional and secure website under Article 6(1)(f) GDPR.",
            "Any non-essential cookie requires prior consent under Article 6(1)(a). Consent is optional and can be withdrawn as easily as it is given."
          ],
          items: [],
          links: []
        },
        %{
          id: "duration",
          title: "6. Duration",
          paragraphs: [
            "The spectre_cookie_consent preference lasts up to 182 days unless you remove it earlier. Technical session cookies expire with the session or after the period strictly required by the requested feature."
          ],
          items: [],
          links: []
        },
        %{
          id: "changes",
          title: "7. Changes to this notice",
          paragraphs: [
            "This Cookie Policy may be updated when the technologies used or legal requirements change. The date shown above identifies the latest revision; changes take effect when published on this page."
          ],
          items: [],
          links: []
        }
      ]
    }
  end

  @spec privacy_policy(String.t()) :: map()
  def privacy_policy("it") do
    %{
      kind: :privacy,
      id: "privacy-policy",
      file: "legal/privacy-gdpr-policy.md",
      eyebrow: "protezione dei dati",
      title: "Privacy e GDPR Policy",
      summary:
        "Questa informativa descrive quali dati personali può trattare spectre.elchemista.com, per quali finalità, con quali basi giuridiche e quali diritti puoi esercitare.",
      updated: "4 agosto 2026",
      sections: [
        %{
          id: "titolare",
          title: "1. Titolare del trattamento",
          paragraphs: [
            "Il titolare del trattamento per questo sito è spectre.elchemista.com, raggiungibile all'indirizzo indicato nella sezione Contatti.",
            "Questa informativa si applica alla navigazione del sito pubblico e alle comunicazioni inviate volontariamente tramite email."
          ],
          items: [],
          links: []
        },
        %{
          id: "dati-raccolti",
          title: "2. Dati che possiamo raccogliere",
          paragraphs: [
            "Il sito è progettato per ridurre al minimo la raccolta di dati personali. A seconda di come lo utilizzi, possono essere trattate le seguenti informazioni."
          ],
          items: [
            %{
              title: "Dati tecnici",
              body:
                "Indirizzo IP, user agent, data e ora, URL richiesto, codici di risposta ed errori possono comparire nei log necessari a erogare e proteggere il servizio."
            },
            %{
              title: "Dati di sessione e sicurezza",
              body:
                "Identificatori firmati, token CSRF e informazioni equivalenti possono essere usati per funzioni protette e prevenzione degli abusi."
            },
            %{
              title: "Preferenze",
              body:
                "La scelta sui cookie viene memorizzata nel cookie spectre_cookie_consent; il tema grafico viene memorizzato nel localStorage del dispositivo."
            },
            %{
              title: "Comunicazioni volontarie",
              body:
                "Se scrivi all'indirizzo email pubblicato, vengono trattati il tuo indirizzo, il contenuto del messaggio e gli eventuali dati che scegli di includere."
            }
          ],
          links: []
        },
        %{
          id: "finalita",
          title: "3. Finalità del trattamento",
          paragraphs: ["I dati vengono trattati esclusivamente per:"],
          items: [
            %{title: "Erogazione", body: "fornire pagine, feed e funzionalità richieste;"},
            %{
              title: "Sicurezza",
              body: "prevenire abusi, frodi, accessi non autorizzati e guasti;"
            },
            %{title: "Preferenze", body: "ricordare le scelte sui cookie e sull'interfaccia;"},
            %{
              title: "Assistenza",
              body: "rispondere alle comunicazioni inviate volontariamente;"
            },
            %{
              title: "Obblighi",
              body: "adempiere a richieste legittime delle autorità o a obblighi di legge."
            }
          ],
          links: []
        },
        %{
          id: "basi-giuridiche",
          title: "4. Basi giuridiche",
          paragraphs: [
            "Il trattamento si fonda, secondo il contesto, sul legittimo interesse a mantenere un servizio sicuro e affidabile, sul consenso per le tecnologie non essenziali, sull'esecuzione di misure richieste dall'interessato e sull'adempimento di obblighi legali.",
            "Quando la base è il consenso, puoi revocarlo in ogni momento senza pregiudicare la liceità del trattamento precedente."
          ],
          items: [],
          links: []
        },
        %{
          id: "destinatari",
          title: "5. Destinatari e responsabili",
          paragraphs: [
            "I dati possono essere trattati da fornitori tecnici strettamente necessari per hosting, rete, sicurezza e posta elettronica, nei limiti del servizio affidato e con adeguati obblighi di riservatezza.",
            "spectre.elchemista.com non vende dati personali e non li cede a intermediari pubblicitari. I dati possono essere comunicati alle autorità solo quando richiesto dalla legge."
          ],
          items: [],
          links: []
        },
        %{
          id: "conservazione",
          title: "6. Conservazione",
          paragraphs: [
            "I log tecnici vengono conservati per il tempo necessario a operatività, diagnosi e sicurezza e poi eliminati o aggregati. La preferenza cookie dura fino a 182 giorni. Le email vengono conservate per il tempo necessario a gestire la richiesta e gli eventuali obblighi conseguenti.",
            "Quando non esiste più una finalità o un obbligo legale, i dati vengono cancellati o anonimizzati."
          ],
          items: [],
          links: []
        },
        %{
          id: "trasferimenti",
          title: "7. Trasferimenti internazionali",
          paragraphs: [
            "Alcuni fornitori infrastrutturali possono trattare dati fuori dallo Spazio Economico Europeo. In tali casi il trasferimento avviene sulla base di una decisione di adeguatezza, clausole contrattuali standard o un altro meccanismo riconosciuto dal GDPR."
          ],
          items: [],
          links: []
        },
        %{
          id: "diritti",
          title: "8. I tuoi diritti GDPR",
          paragraphs: [
            "Nei casi previsti dagli articoli 15–22 del GDPR puoi esercitare i seguenti diritti contattando il titolare."
          ],
          items: [
            %{title: "Accesso", body: "ottenere conferma e copia dei dati trattati;"},
            %{title: "Rettifica", body: "correggere dati inesatti o incompleti;"},
            %{
              title: "Cancellazione",
              body: "chiedere la cancellazione quando ne ricorrono i presupposti;"
            },
            %{title: "Limitazione", body: "limitare temporaneamente alcuni trattamenti;"},
            %{
              title: "Opposizione",
              body: "opporti ai trattamenti fondati sul legittimo interesse;"
            },
            %{
              title: "Portabilità",
              body: "ricevere i dati in formato strutturato, quando applicabile;"
            },
            %{title: "Revoca", body: "ritirare in qualsiasi momento un consenso già prestato."}
          ],
          links: []
        },
        %{
          id: "reclamo",
          title: "9. Reclamo all'autorità",
          paragraphs: [
            "Hai il diritto di proporre reclamo all'autorità di controllo competente. In Italia puoi rivolgerti al Garante per la protezione dei dati personali, senza pregiudicare altri rimedi amministrativi o giudiziari."
          ],
          items: [],
          links: [
            %{
              label: "Garante per la protezione dei dati personali",
              href: "https://www.garanteprivacy.it/"
            }
          ]
        },
        %{
          id: "sicurezza",
          title: "10. Sicurezza e link esterni",
          paragraphs: [
            "Sono adottate misure tecniche e organizzative ragionevoli per proteggere i dati da perdita, alterazione, divulgazione o accesso non autorizzato. Nessun sistema connesso a Internet può tuttavia garantire sicurezza assoluta.",
            "Il sito può contenere link a servizi esterni. Le loro pratiche privacy sono disciplinate dalle rispettive informative e non sono controllate da spectre.elchemista.com."
          ],
          items: [],
          links: []
        },
        %{
          id: "modifiche",
          title: "11. Modifiche all'informativa",
          paragraphs: [
            "Questa informativa può essere aggiornata per riflettere modifiche tecniche, operative o normative. La data in alto identifica l'ultima revisione; la versione aggiornata entra in vigore con la pubblicazione."
          ],
          items: [],
          links: []
        }
      ]
    }
  end

  def privacy_policy("en") do
    %{
      kind: :privacy,
      id: "privacy-policy",
      file: "legal/privacy-gdpr-policy.md",
      eyebrow: "data protection",
      title: "Privacy and GDPR Policy",
      summary:
        "This notice describes which personal data spectre.elchemista.com may process, for which purposes and legal bases, and the rights you can exercise.",
      updated: "August 4, 2026",
      sections: [
        %{
          id: "controller",
          title: "1. Data controller",
          paragraphs: [
            "The data controller for this website is spectre.elchemista.com and can be reached using the address in the Contact section.",
            "This notice applies to use of the public website and to communications you voluntarily send by email."
          ],
          items: [],
          links: []
        },
        %{
          id: "data-collected",
          title: "2. Data we may collect",
          paragraphs: [
            "The site is designed to minimize personal data collection. Depending on how you use it, the following information may be processed."
          ],
          items: [
            %{
              title: "Technical data",
              body:
                "IP address, user agent, date and time, requested URL, response codes, and errors may appear in logs required to deliver and protect the service."
            },
            %{
              title: "Session and security data",
              body:
                "Signed identifiers, CSRF tokens, and equivalent information may be used for restricted features and abuse prevention."
            },
            %{
              title: "Preferences",
              body:
                "Your cookie choice is stored in the spectre_cookie_consent cookie; the visual theme is stored in your device's localStorage."
            },
            %{
              title: "Voluntary communications",
              body:
                "If you write to the published email address, your address, message, and any information you choose to include are processed."
            }
          ],
          links: []
        },
        %{
          id: "purposes",
          title: "3. Purposes of processing",
          paragraphs: ["Data is processed only to:"],
          items: [
            %{title: "Delivery", body: "provide the pages, feeds, and features you request;"},
            %{
              title: "Security",
              body: "prevent abuse, fraud, unauthorized access, and failures;"
            },
            %{title: "Preferences", body: "remember cookie and interface choices;"},
            %{title: "Support", body: "reply to communications you voluntarily send;"},
            %{
              title: "Compliance",
              body: "respond to lawful authority requests and meet legal obligations."
            }
          ],
          links: []
        },
        %{
          id: "legal-bases",
          title: "4. Legal bases",
          paragraphs: [
            "Depending on the context, processing relies on the legitimate interest in maintaining a secure and reliable service, consent for non-essential technologies, steps requested by the data subject, or compliance with legal obligations.",
            "Where consent is the basis, you may withdraw it at any time without affecting processing that was lawful before withdrawal."
          ],
          items: [],
          links: []
        },
        %{
          id: "recipients",
          title: "5. Recipients and processors",
          paragraphs: [
            "Data may be processed by technical providers strictly required for hosting, networking, security, and email, within the scope of their service and under appropriate confidentiality obligations.",
            "spectre.elchemista.com does not sell personal data or disclose it to advertising brokers. Data may be disclosed to authorities only where required by law."
          ],
          items: [],
          links: []
        },
        %{
          id: "retention",
          title: "6. Retention",
          paragraphs: [
            "Technical logs are kept for the time required for operation, diagnosis, and security and are then deleted or aggregated. The cookie preference lasts up to 182 days. Emails are retained as long as needed to handle the request and any resulting obligations.",
            "When there is no longer a purpose or legal obligation, data is deleted or anonymized."
          ],
          items: [],
          links: []
        },
        %{
          id: "transfers",
          title: "7. International transfers",
          paragraphs: [
            "Some infrastructure providers may process data outside the European Economic Area. Where this occurs, transfers rely on an adequacy decision, standard contractual clauses, or another mechanism recognized by the GDPR."
          ],
          items: [],
          links: []
        },
        %{
          id: "rights",
          title: "8. Your GDPR rights",
          paragraphs: [
            "Where Articles 15–22 GDPR apply, you may exercise the following rights by contacting the controller."
          ],
          items: [
            %{title: "Access", body: "obtain confirmation and a copy of processed data;"},
            %{title: "Rectification", body: "correct inaccurate or incomplete data;"},
            %{title: "Erasure", body: "request deletion where the legal conditions are met;"},
            %{title: "Restriction", body: "temporarily limit certain processing;"},
            %{title: "Objection", body: "object to processing based on legitimate interests;"},
            %{
              title: "Portability",
              body: "receive data in a structured format, where applicable;"
            },
            %{title: "Withdrawal", body: "withdraw previously given consent at any time."}
          ],
          links: []
        },
        %{
          id: "complaint",
          title: "9. Complaint to an authority",
          paragraphs: [
            "You have the right to lodge a complaint with the competent supervisory authority, without affecting any other administrative or judicial remedy."
          ],
          items: [],
          links: [
            %{
              label: "Italian Data Protection Authority",
              href: "https://www.garanteprivacy.it/"
            }
          ]
        },
        %{
          id: "security",
          title: "10. Security and external links",
          paragraphs: [
            "Reasonable technical and organizational measures are used to protect data against loss, alteration, disclosure, or unauthorized access. No Internet-connected system can guarantee absolute security.",
            "The site may contain links to external services. Their privacy practices are governed by their own notices and are not controlled by spectre.elchemista.com."
          ],
          items: [],
          links: []
        },
        %{
          id: "changes",
          title: "11. Changes to this notice",
          paragraphs: [
            "This notice may be updated to reflect technical, operational, or legal changes. The date above identifies the latest revision; the updated version takes effect when it is published."
          ],
          items: [],
          links: []
        }
      ]
    }
  end
end
