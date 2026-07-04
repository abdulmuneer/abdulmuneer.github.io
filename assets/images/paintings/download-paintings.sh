#!/usr/bin/env bash
#
# Downloads the public-domain source paintings (Wikimedia Commons) chosen as
# classical banners for the "Future of Agentic Engineering" series.
#
# All six works are old enough to be in the public domain; the files below are
# the Wikimedia Commons digitizations (mostly Google Art Project scans).
#
# Run from anywhere:
#   bash assets/images/paintings/download-paintings.sh
#
# Files are saved next to this script, scaled to 2000px wide (plenty for a web
# banner; edit WIDTH below for full resolution by setting it empty).

set -euo pipefail
cd "$(dirname "$0")"

WIDTH=2000
BASE="https://commons.wikimedia.org/wiki/Special:FilePath"

dl () {  # dl <commons-filename> <output-name>
  local q=""
  [ -n "$WIDTH" ] && q="?width=$WIDTH"
  echo "-> $2"
  curl -fL --retry 3 --retry-delay 2 -o "$2" "$BASE/$1$q"
}

# page / theme                     commons filename                                                        saved as
dl "The_School_of_Athens_by_Raphael_(Vatican).jpg"                        "landing-school-of-athens.jpg"   # Raphael, orchestration
dl "Johannes_Vermeer_-_The_Geographer_-_Google_Art_Project.jpg"          "part1-vermeer-geographer.jpg"   # Vermeer, disciplined craft
dl "Da_Vinci_Vitruve_Luc_Viatour.jpg"                                    "part2-vitruvian-man.jpg"        # Leonardo, breadth + proportion
dl "The_Great_Wave_off_Kanagawa.jpg"                                     "part3-great-wave.jpg"           # Hokusai, force held in a frame
dl "Pieter_Bruegel_the_Elder-_The_Harvesters_-_Google_Art_Project.jpg"   "part4-harvesters.jpg"           # Bruegel, bounded accumulation
dl "Rembrandt_Harmensz._van_Rijn_-_The_Return_of_the_Prodigal_Son.jpg"   "part5-prodigal-son.jpg"         # Rembrandt, care

# Alternates mentioned in the brief (uncomment to fetch):
# dl "Johannes_Vermeer_-_The_Astronomer.jpg"                             "part1-vermeer-astronomer.jpg"   # Vermeer alt for Part 1
# dl "Pieter_Bruegel_the_Elder_-_Children%E2%80%99s_Games_-_Google_Art_Project.jpg" "part5-childrens-games.jpg"  # Bruegel alt for Part 5

echo "Done. Saved in $(pwd)"
