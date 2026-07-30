#!/bin/sh
# spec/ est la seule source de vérité (voir spec/README.md). Ce script échoue si une copie
# embarquée diverge de spec/ : games/ -> Catalog/GameDefinitions (l'app), golden/ -> CatalogTests
# (les tests ne peuvent pas référencer spec/ directement, SwiftPM exige des ressources locales
# à la cible).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
status=0

check_pair() {
    label="$1"
    spec_dir="$2"
    copy_dir="$3"

    for spec_file in "$spec_dir"/*.json; do
        [ -e "$spec_file" ] || continue
        name="$(basename "$spec_file")"
        copy_file="$copy_dir/$name"
        if [ ! -f "$copy_file" ]; then
            echo "error: $name manque dans $label (présent dans spec/)"
            status=1
            continue
        fi
        if ! diff -q "$spec_file" "$copy_file" > /dev/null 2>&1; then
            echo "error: $name diverge entre spec/ et $label"
            status=1
        fi
    done

    for copy_file in "$copy_dir"/*.json; do
        [ -e "$copy_file" ] || continue
        name="$(basename "$copy_file")"
        if [ ! -f "$spec_dir/$name" ]; then
            echo "error: $name présent dans $label mais absent de spec/"
            status=1
        fi
    done
}

check_pair "Catalog/GameDefinitions" "$ROOT/spec/games" "$ROOT/CaCompteKit/Sources/Catalog/GameDefinitions"
check_pair "Tests/CatalogTests/GoldenResources" "$ROOT/spec/golden" "$ROOT/CaCompteKit/Tests/CatalogTests/GoldenResources"

if [ "$status" -eq 0 ]; then
    echo "spec/ et ses copies embarquées sont synchronisés."
fi

exit $status
