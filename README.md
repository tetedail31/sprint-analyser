# Sprint Analyser

Analyse vidéo de course — application monofichier (MediaPipe), publiée en statique.

- **Site en ligne** : https://tetedail31.github.io/sprint-analyser/
- **Hébergement** : GitHub Pages, branche `gh-pages` (contenu de `dist/` à la racine)
- **Source** : branche `main` (ce dépôt)

## Structure

- `src/index.html` — l'application, source unique de vérité
- `dist/` — artefact servi (`index.html` + `404.html`, copies identiques ; généré, peut être supprimé)
- `deploy.sh` — publication complète : contrôle du jeton, création du dépôt si absent, build de `dist/`, push sur `gh-pages`, activation de Pages, attente du build, vérification HTTP 200

## Redéployer

```sh
sh deploy.sh          # publie et vérifie ; affiche l'URL seulement après un 200
sh deploy.sh --check  # contrôle jeton + dépôt, ne pousse rien
```

Le script lit le jeton dans `GITHUB_TOKEN`, `GH_TOKEN`, `.gh_token` (ligne `GITHUB_TOKEN=…`) ou `~/.git-credentials`.
Il ne l'écrit jamais dans `.git/config` : l'authentification passe par un en-tête éphémère.

## Jeton requis (fine-grained PAT)

- Repository access : **All repositories** (ou le dépôt `sprint-analyser`)
- Repository permissions : **Contents: Read and write**, **Pages: Read and write**
- Account permissions : **Administration: Read and write** — seulement si le dépôt doit être créé par le script

Sans *Administration*, créer le dépôt vide à la main sur github.com ; le reste du script fonctionne.
Révoquer le jeton après usage : seul le redéploiement en a besoin.

## Retour arrière

Chaque déploiement pose une étiquette `deploy-AAAAMMJJ-HHMM` dans `.pages-work/` (branche `gh-pages`).
Republier une version antérieure :

```sh
cd .pages-work && git checkout <étiquette> -- . && git commit -m "rollback" && git push origin gh-pages
```

## Dépendances externes

L'analyse charge MediaPipe depuis *jsdelivr* et *storage.googleapis.com*. Si ces CDN sont
inaccessibles, la page s'affiche mais l'analyse échoue — ce n'est pas un défaut d'hébergement.

## Reprise après perte de l'environnement de travail

Rien de local n'est indispensable : `git clone https://github.com/tetedail31/sprint-analyser.git`,
puis `sh deploy.sh` avec un jeton valide. Le `404.html` est régénéré automatiquement depuis `src/index.html`.
