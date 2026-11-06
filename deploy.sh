#!/bin/sh
# Déploiement de Sprint Analyser (site statique de dist/) sur GitHub Pages.
#
#   sh deploy.sh              # déploie et affiche l'URL publique
#   sh deploy.sh --check      # contrôle jeton + dépôt, ne pousse rien
#
# Jeton attendu : fine-grained PAT avec, au minimum,
#   • Repository access : All repositories (ou le dépôt sprint-analyser)
#   • Repository permissions : Contents = Read and write, Pages = Read and write
#   • Account permissions : Administration = Read and write (uniquement pour CRÉER le dépôt)
# Sinon un PAT classique avec le scope « repo ».
#
# Le jeton n'est jamais écrit sur disque ni dans l'URL du remote : il est passé
# à git par un en-tête HTTP éphémère (http.extraheader).
set -u

PROJECT="${GITHUB_PROJECT:-sprint-analyser}"
BRANCH="${GITHUB_BRANCH:-gh-pages}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
WORK="$ROOT/.pages-work"
API="https://api.github.com"

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

die() { printf 'ÉCHEC : %s\n' "$1" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------- 1. jeton
echo "== 1. Jeton"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  for f in "$ROOT/.gh_token" "$HOME/.gh_token"; do
    [ -f "$f" ] || continue
    line=$(grep -m1 -E '^(GITHUB_TOKEN|GH_TOKEN)=' "$f" 2>/dev/null) || continue
    TOKEN=$(printf '%s' "$line" | cut -d= -f2- | tr -d ' \r\n')
    [ -n "$TOKEN" ] && { echo "   jeton lu dans $f"; break; }
  done
fi
if [ -z "$TOKEN" ] && [ -f "$HOME/.git-credentials" ]; then
  TOKEN=$(grep -m1 'github.com' "$HOME/.git-credentials" | sed -E 's#^https://[^:]*:([^@]*)@.*#\1#')
  [ -n "$TOKEN" ] && echo "   jeton lu dans ~/.git-credentials"
fi
[ -n "$TOKEN" ] || die "aucun jeton (GITHUB_TOKEN, GH_TOKEN, .gh_token ou ~/.git-credentials)" 2
echo "   ${#TOKEN} caractères, préfixe $(printf '%.11s' "$TOKEN")…"

api() { # api METHODE CHEMIN [corps] -> code HTTP sur stdout, réponse dans $ROOT/.api.json
  _m=$1; _p=$2; _b=${3:-}
  if [ -n "$_b" ]; then
    nx curl -sS -m 40 -X "$_m" -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "User-Agent: sprint-analyser-deploy" -d "$_b" "$API$_p" -o "$ROOT/.api.json" -w '%{http_code}'
  else
    nx curl -sS -m 40 -X "$_m" -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "User-Agent: sprint-analyser-deploy" "$API$_p" -o "$ROOT/.api.json" -w '%{http_code}'
  fi
}
field() { python3 -c "import json,sys;d=json.load(open('$ROOT/.api.json'));print(d$1 if d$1 is not None else '')" 2>/dev/null; }

code=$(api GET /user)
[ "$code" = "200" ] || die "jeton refusé par GitHub (HTTP $code) : $(field "['message']")" 3
OWNER="${GITHUB_OWNER:-$(field "['login']")}"
[ -n "$OWNER" ] || die "impossible de lire le compte du jeton" 3
echo "   compte : $OWNER"

# ------------------------------------------------------- 2. dépôt cible
echo "== 2. Dépôt $OWNER/$PROJECT"
code=$(api GET "/repos/$OWNER/$PROJECT")
if [ "$code" = "200" ]; then
  echo "   dépôt existant"
else
  echo "   dépôt absent — création"
  code=$(api POST /user/repos "{\"name\":\"$PROJECT\",\"description\":\"Sprint Analyser — analyse vidéo de course\",\"private\":false,\"has_issues\":false,\"has_wiki\":false,\"auto_init\":false}")
  case "$code" in
    201) echo "   dépôt créé (public)" ;;
    422) echo "   dépôt déjà présent (422) — on continue" ;;
    403) die "le jeton ne peut pas créer de dépôt (403 : $(field "['message']")).
   → soit créer le dépôt vide $PROJECT à la main sur github.com,
   → soit régénérer le jeton avec Account permissions → Administration: Read and write,
     et Repository access → All repositories." 4 ;;
    *) die "création refusée (HTTP $code) : $(field "['message']")" 4 ;;
  esac
fi
REPO_URL="https://github.com/$OWNER/$PROJECT.git"

if [ "$check_only" = "1" ]; then
  echo "== contrôles OK — rien n'a été poussé"; exit 0
fi

# ------------------------------------------------- 3. branche de déploiement
# ------------------------------------------------ 2bis. construction de dist/
echo "== 3. Préparation de dist/"
if [ -f "$ROOT/src/index.html" ]; then
  mkdir -p "$DIST"
  if [ ! -f "$DIST/index.html" ] || [ "$ROOT/src/index.html" -nt "$DIST/index.html" ]; then
    cp "$ROOT/src/index.html" "$DIST/index.html"
    cp "$ROOT/src/index.html" "$DIST/404.html"
    echo "   dist/ régénéré depuis src/index.html ($(wc -c < "$DIST/index.html") octets)"
  else
    echo "   dist/ déjà à jour ($(wc -c < "$DIST/index.html") octets)"
  fi
fi

echo "== 4. Contenu de dist/ → branche $BRANCH"
[ -f "$DIST/index.html" ] || die "dist/index.html manquant" 5
mkdir -p "$WORK"
cd "$WORK" || die "répertoire de travail inaccessible" 5
[ -d .git ] || git init -q -b "$BRANCH"
git config user.name "$OWNER"
git config user.email "$OWNER@users.noreply.github.com"
git config advice.defaultBranchName false
# on vide tout sauf .git, puis on recopie dist/
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -a "$DIST/." .
git add -A
if git diff --cached --quiet 2>/dev/null && [ -n "$(git rev-parse HEAD 2>/dev/null)" ]; then
  echo "   aucun changement depuis le dernier déploiement"
else
  TAG="deploy-$(date +%Y%m%d-%H%M)"
  git commit -q -m "deploy: $TAG"
  git tag -f "$TAG" >/dev/null 2>&1
  echo "   commit $(git rev-parse --short HEAD) — étiquette $TAG"
fi
git remote remove origin 2>/dev/null
git remote add origin "$REPO_URL"
HDR="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\n')"
if ! git -c http.extraheader="$HDR" push -q -f origin "$BRANCH" 2>/tmp/push.err; then
  grep -viE 'authorization' /tmp/push.err | head -5 >&2
  die "git push a échoué — droits Contents: Read and write ?" 6
fi
git -c http.extraheader="$HDR" push -q -f origin --tags >/dev/null 2>&1 || true
# vérification : la branche distante doit exister
code=$(api GET "/repos/$OWNER/$PROJECT/branches/$BRANCH")
[ "$code" = "200" ] \
  || die "la branche $BRANCH n'est pas sur le dépôt (HTTP $code) — pousser a échoué (droits Contents ?)" 6
echo "   branche $BRANCH confirmée sur le dépôt"

# ------------------------------------------------------------ 4. GitHub Pages
echo "== 5. Activation de Pages"
SRC="{\"source\":{\"branch\":\"$BRANCH\",\"path\":\"/\"}}"
code=$(api GET "/repos/$OWNER/$PROJECT/pages")
if [ "$code" = "200" ]; then
  echo "   Pages déjà activé — mise à jour de la source"
  code=$(api PUT "/repos/$OWNER/$PROJECT/pages" "$SRC")
else
  code=$(api POST "/repos/$OWNER/$PROJECT/pages" "$SRC")
fi
case "$code" in
  200|201|204) echo "   source : $BRANCH:/" ;;
  403) die "le jeton n'a pas la permission Pages: Read and write (403 : $(field "['message']"))" 7 ;;
  *) die "activation refusée (HTTP $code) : $(field "['message']")" 7 ;;
esac
URL=$(field "['html_url']")
[ -n "$URL" ] || URL="https://$OWNER.github.io/$PROJECT/"

# ------------------------------------------------------------- 5. attente du build
echo "== 6. Attente de la publication"
i=0
while [ "$i" -lt 30 ]; do
  code=$(api GET "/repos/$OWNER/$PROJECT/pages/builds/latest")
  st=$(field "['status']")
  echo "   essai $((i+1))/30 : $st"
  [ "$st" = "built" ] && break
  [ "$st" = "errored" ] && die "le build Pages a échoué : $(field "['error']['message']")" 8
  i=$((i+1)); sleep 6
done
[ "$st" = "built" ] || echo "   (build encore en cours — l'URL peut répondre sous une minute)"

# --------------------------------------------------------- 6. vérification HTTP
echo "== 7. Vérification publique"
i=0
while [ "$i" -lt 10 ]; do
  code=$(nx curl -sS -m 25 -o "$ROOT/.live.html" -w '%{http_code}' "$URL" 2>/dev/null)
  echo "   essai $((i+1))/10 : HTTP $code"
  [ "$code" = "200" ] && break
  i=$((i+1)); sleep 8
done
if [ "$code" = "200" ]; then
  echo "   titre servi : $(grep -o '<title>[^<]*</title>' "$ROOT/.live.html" | head -1)"
  echo
  echo "SITE EN LIGNE : $URL"
else
  die "l'URL ne répond pas 200 (dernier code $code)" 9
fi
