# Contratto dei contenuti Markdown

La repository configurata è la sorgente canonica del blog. ExBlog legge e
scrive soltanto file `.md` sotto `EX_BLOG_CONTENT_ROOT`, che per default vale
`content`.

## Struttura

```text
content/
├── it/
│   └── 2026-08-03-un-esempio.md
└── en/
    └── 2026-08-03-an-example.md
```

Ogni lingua deve essere presente in `EX_BLOG_SUPPORTED_LANGUAGES`. Il nome
canonico generato dall’agente è `YYYY-MM-DD-slug.md`; parser e indice accettano
anche un nome senza prefisso data se `date` è presente nel front matter.

## Front matter

Il documento inizia con YAML delimitato da `---`, seguito dal corpo CommonMark:

```markdown
---
title: "Un esempio completo"
slug: "un-esempio-completo"
lang: "it"
status: "draft"
date: "2026-08-03"
updated: "2026-08-03"
category: "Tecnologia"
tags: ["elixir", "phoenix"]
seo_title: "Un esempio completo in Elixir"
seo_description: "Una descrizione concisa, entro 160 caratteri."
cover: "/images/articles/sha256-del-file.webp"
cover_alt: "Una pagina di codice Elixir"
translation_of: null
---

## Titolo della prima sezione

Il corpo dell’articolo usa **CommonMark**.
```

Campi:

| Campo | Regola |
| --- | --- |
| `title` | titolo editoriale; se omesso in lettura deriva dallo slug |
| `slug` | minuscolo, numeri e trattini; se omesso deriva dal filename |
| `lang` | codice lingua supportato; se omesso deriva dalla directory |
| `status` | esclusivamente `draft` o `published`; default `draft` |
| `date` | data ISO `YYYY-MM-DD`; può derivare dal filename |
| `updated` | data ISO dell’ultima revisione; default uguale a `date` |
| `category` | categoria singola opzionale |
| `tags` | lista YAML o stringa separata da virgole |
| `seo_title` | opzionale, massimo 60 caratteri nelle scritture dell’agente |
| `seo_description` | opzionale, massimo 160 caratteri |
| `cover` | URL HTTPS o percorso pubblico sicuro che inizia con `/`; gli upload Telegram usano `/images/articles/<sha256>.<ext>` |
| `cover_alt` | testo alternativo accessibile; per una foto Telegram deriva dalla didascalia o dal fallback sul titolo |
| `translation_of` | path repository-relative dell’articolo origine |

Per collegare le traduzioni, ogni variante usa lo stesso path origine. Esempio:

```yaml
translation_of: "content/it/2026-08-03-un-esempio.md"
```

L’articolo origine non è obbligato a dichiarare `translation_of`: il proprio
path diventa automaticamente l’identificatore del gruppo.

## Rendering e validazione

`YamlElixir` decodifica il front matter. `MDEx` applica CommonMark con autolink,
footnote, strikethrough, tabelle e task list, poi sanitizza l’HTML. JavaScript,
handler HTML e markup pericoloso non vengono pubblicati.

YAML rotto, front matter assente, date invalide, status sconosciuti, slug o
lingue malformati producono una voce di audit `invalid`; non interrompono il
rebuild dell’intero indice e non sono visibili sul blog.

## Scritture dell’agente

Le scritture seguono sempre questa sequenza:

```text
validazione → path confinato sotto content/ → file canonico → git add/commit
→ fetch/rebase/push → rebuild ETS → rilettura dell’articolo
```

Slug e lingua di un articolo esistente non vengono cambiati da un update. Una
traduzione è un nuovo draft. Pubblicazione e rimozione modificano il repository
e richiedono conferma nelle superfici agentiche.

Nel flow `/create`, corpo e SEO opzionale vengono generati via OpenRouter solo
dopo la conferma Spectre. La risposta SEO viene normalizzata nei campi
`seo_title`, `seo_description`, `cover_alt` e `tags` prima che il Writer applichi
i limiti del contratto e serializzi il file.

## Asset di copertina Telegram

L’amministratore può inviare una foto mentre `article_creation` è attivo.
`ex_gram` scarica i byte tramite il file id TDLib; ExBlog accetta JPEG, PNG,
WebP e GIF fino a 10 MB, determina il formato dai magic bytes e usa SHA-256 come
nome. Il filename Telegram non viene mai riutilizzato.

La copia servita da Phoenix è:

```text
priv/static/images/articles/<sha256>.<estensione>
```

Il backing durevole è:

```text
$EX_BLOG_DATA_DIR/assets/images/articles/<sha256>.<estensione>
```

Al boot il backing viene validato e ripristinato nella directory statica della
release. Il Markdown conserva soltanto il path pubblico in `cover`; byte, file
id Telegram e path locali TDLib non entrano nel front matter o nello stato
Spectre.
