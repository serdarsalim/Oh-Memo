#!/bin/zsh

OUTPUT_FILE="/Users/slm/Desktop/all_transcripts.txt"
EXTRACTOR="/Users/slm/my-portfolio/extract-apple-voice-memos-transcript/extract-apple-voice-memos-transcript"
RECORDINGS_DIR="/Users/slm/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"

EXCLUDE_LIST=(
"20250825 093238-5C92A92C"
"20250826 133710-C8214BF9"
"20250828 154237-46AEFF02"
"20250829 152746-C705148A"
"20250922 185250-9CB5DB27"
"20251007 101230-22F4740A"
"20251103 180300-B90330E3"
"20251103 175335-68A46BCA"
"20251007 102344-0EC31359"
"20251007 101914-5A77B049"
)

: > "$OUTPUT_FILE"

for f in "$RECORDINGS_DIR"/*.m4a(On); do
  if [ -f "$f" ]; then

    BASENAME=$(basename "$f" .m4a)

    # Skip excluded files
    if [[ " ${EXCLUDE_LIST[@]} " =~ " ${BASENAME} " ]]; then
      continue
    fi

    # Extract date & time from filename
    DATE_PART="${BASENAME:0:8}"
    TIME_PART="${BASENAME:9:6}"

    FORMATTED_DATE="${DATE_PART:0:4}-${DATE_PART:4:2}-${DATE_PART:6:2}"
    FORMATTED_TIME="${TIME_PART:0:2}:${TIME_PART:2:2}:${TIME_PART:4:2}"

    TRANSCRIPT="$("$EXTRACTOR" "$f" 2>/dev/null)"

    if [ -n "$TRANSCRIPT" ]; then
      echo "================================" >> "$OUTPUT_FILE"
      echo "Name: " >> "$OUTPUT_FILE"
      echo "Recording: $BASENAME" >> "$OUTPUT_FILE"
      echo "Date: $FORMATTED_DATE" >> "$OUTPUT_FILE"
      echo "Time: $FORMATTED_TIME" >> "$OUTPUT_FILE"
      echo "" >> "$OUTPUT_FILE"
      echo "$TRANSCRIPT" >> "$OUTPUT_FILE"
      echo "" >> "$OUTPUT_FILE"
      echo "" >> "$OUTPUT_FILE"
    fi
  fi
done