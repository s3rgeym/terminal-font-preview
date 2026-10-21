#!/usr/bin/env bash

set -Eeuo pipefail

FONT_SIZE="${FONT_SIZE:-12}"
DELAY="${DELAY:-2}"
RESULT="${RESULT:-$PWD/preview.png}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for cmd in fc-list alacritty nvim spectacle ffmpeg magick awk; do
  command -v "$cmd" >/dev/null || {
    printf 'Не найдена команда: %s\n' "$cmd" >&2
    exit 1
  }
done

cat >"$TMP/template.py" <<'PY'
"""Python font specimen."""


class User:
    """Represent a user account."""

    def __init__(self, name: str, age: int = 25) -> None:
        # Initialize the object with user information.
        self.name = name
        self.age = age

    @property
    def is_adult(self) -> bool:
        """Return whether the user is an adult."""
        return self.age >= 18

    def greet(self) -> str:
        # Format a greeting using an f-string.
        return f"Hello, {self.name}!"


class Repository:
    """Store and retrieve users."""

    def __init__(self) -> None:
        self._users: list[User] = []

    def add(self, user: User) -> None:
        # Append the user to the internal collection.
        self._users.append(user)

    def find(self, name: str) -> User | None:
        # Return the first matching user, if any.
        return next(
            (user for user in self._users if user.name == name),
            None,
        )


def main() -> None:
    repository = Repository()
    repository.add(User("Alice", 30))

    user = repository.find("Alice")
    if user is not None:
        print(user.greet())
        print(f"Adult: {user.is_adult}")


if __name__ == "__main__":
    main()
PY

mapfile -t fonts < <(
  fc-list --format '%{family[0]}\t%{style}\n' |
    awk -F '\t' '$2 ~ /(^|,)Regular(,|$)/ { print $1 }' |
    grep -iE 'Nerd Font Mono$' |
    grep -iv 'NL' |
    sort -fu
)

if ((${#fonts[@]} == 0)); then
  echo "Nerd Font Mono не найдены." >&2
  exit 1
fi

mkdir -p "$(dirname "$RESULT")"

index=0
total=${#fonts[@]}

for font in "${fonts[@]}"; do
  ((index += 1))

  config="$TMP/alacritty.toml"
  preview="$TMP/preview.py"
  raw="$TMP/raw.png"
  shot="$TMP/$(printf '%04d' "$index").png"

  printf '[%d/%d] %s\n' "$index" "$total" "$font"

  sed "1s|.*|# Font: $font (${FONT_SIZE}pt)|" \
    "$TMP/template.py" >"$preview"

  cat >"$config" <<TOML
[window]
decorations = "None"
opacity = 1.0
startup_mode = "Windowed"
dynamic_padding = false
padding = { x = 0, y = 0 }
dimensions = { columns = 120, lines = 50 }

[scrolling]
history = 0

[font]
size = $FONT_SIZE

[font.normal]
family = "$font"
TOML

  alacritty \
    --config-file "$config" \
    --title "$font" \
    --class FontPreview \
    -e nvim -n -R "$preview" &
  pid=$!

  sleep "$DELAY"

  if ! spectacle -a -b -n -o "$raw"; then
    printf 'Не удалось сделать скриншот: %s\n' "$font" >&2
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    continue
  fi

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  ffmpeg -hide_banner -loglevel error -y \
    -i "$raw" \
    "$shot"
done

mapfile -t images < <(
  find "$TMP" -maxdepth 1 -type f -name '[0-9]*.png' | sort
)

if ((${#images[@]} == 0)); then
  echo "Нет скриншотов для сборки." >&2
  exit 1
fi

min_width=$(
  magick identify -format '%w\n' "${images[@]}" |
    sort -n |
    head -n 1
)

magick "${images[@]}" \
  -resize "${min_width}x" \
  -bordercolor '#444444' \
  -border 0x2 \
  -append "$RESULT"

printf '\nГотово: %s (%d шрифтов, ширина %s px)\n' \
  "$RESULT" "${#images[@]}" "$min_width"
