#!/bin/bash

set -euo pipefail
DATA_DIR="data"
OUTPUT_DIR="output"
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/project.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'     
log() {
    local type="$1"
    local color="$2"
    local msg="$3"
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${color}[$now] [$type] $msg${NC}"      # show on screen
    echo "[$now] [$type] $msg" >> "$LOG_FILE"       # save in log file
}

log_info()    { log "INFO"    "$BLUE"   "$1"; }
log_success() { log "SUCCESS" "$GREEN"  "$1"; }
log_warning() { log "WARNING" "$YELLOW" "$1"; }
log_error()   { log "ERROR"   "$RED"    "$1"; }


trap 'echo; log_error "Script interrupted by user."; exit 1' INT
trap 'log_error "An unexpected error occurred."' ERR


check_file() {
    local file="$1"

    if [ ! -e "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    if [ ! -f "$file" ]; then
        log_error "Not a regular file: $file"
        return 1
    fi
    if [ ! -r "$file" ]; then
        log_error "File is not readable: $file"
        return 1
    fi
    if [ ! -s "$file" ]; then
        log_error "File is empty: $file"
        return 1
    fi
    return 0
}

command_exists() {
    if command -v "$1" > /dev/null 2>&1; then
        log_success "$1 is installed."
        return 0
    else
        log_error "$1 is not installed."
        return 1
    fi
}

check_dependencies() {
    log_info "Checking dependencies..."
    local missing=0
    local cmd
    for cmd in awk sed grep sort wc cut; do
        command_exists "$cmd" || missing=$((missing + 1))
    done

    if [ "$missing" -gt 0 ]; then
        log_error "$missing command(s) missing."
        return 1
    fi
    log_success "All dependencies are available."
}

init_directories() {
    mkdir -p "$DATA_DIR" "$OUTPUT_DIR" "$LOG_DIR"
    log_info "Initializing directories..."
    log_success "Required directories are ready."
}
count_lines() {
    local file="$1"
    check_file "$file" || return 1

    log_info "Counting lines in $file"
    local total
    total=$(awk 'END {print NR}' "$file")
    log_success "Number of lines: $total"
}

extract_columns() {
    local file="$1"
    local columns="$2"
    check_file "$file" || return 1

    if [ -z "$columns" ]; then
        log_error "Columns cannot be empty."
        return 1
    fi

   
    local total
    total=$(awk -F',' 'NR==1 {print NF}' "$file")

    # split "1,3,5" into an array, then check every number
    local cols
    IFS=',' read -a cols <<< "$columns"
    local c
    for c in "${cols[@]}"; do
        if ! [ "$c" -ge 1 ] 2>/dev/null || [ "$c" -gt "$total" ]; then
            log_error "Invalid column number: $c"
            return 1
        fi
    done

    log_info "Extracting columns $columns from $file"
    cut -d',' -f"$columns" "$file" > "$OUTPUT_DIR/columns.csv"
    cat "$OUTPUT_DIR/columns.csv"
    log_success "Saved to $OUTPUT_DIR/columns.csv"
}


filter_data() {
    local file="$1"
    local pattern="$2"
    check_file "$file" || return 1

    log_info "Filtering $file with pattern: $pattern"
    local status=0
    grep -E "$pattern" "$file" > "$OUTPUT_DIR/filtered.txt" 2> /dev/null || status=$?

    if [ "$status" -eq 0 ]; then
        cat "$OUTPUT_DIR/filtered.txt"
        log_success "Saved to $OUTPUT_DIR/filtered.txt"
    elif [ "$status" -eq 1 ]; then
        log_warning "No matching records found."
    else
        log_error "Invalid regular expression: $pattern"
        return 1
    fi
}


calculate_stats() {
    local file="$1"
    check_file "$file" || return 1

    log_info "Calculating statistics for $file"
    if awk '
        $1 ~ /^-?[0-9]+(\.[0-9]+)?$/ {
            n = $1 + 0
            count++
            sum += n
            if (count == 1 || n < min) min = n
            if (count == 1 || n > max) max = n
        }
        END {
            if (count == 0) exit 1
            print "Statistics"
            print "----------------"
            print "Count   : " count
            print "Minimum : " min
            print "Maximum : " max
            print "Average : " sum / count
        }
    ' "$file"; then
        log_success "Statistics calculated."
    else
        log_error "No numeric data found in $file"
        return 1
    fi
}

# 5) merge_files FILE1 FILE2 ...
merge_files() {
    if [ $# -lt 2 ]; then
        log_error "Please provide at least 2 files."
        return 1
    fi

    local f
    for f in "$@"; do
        check_file "$f" || return 1
    done

    cat "$@" > "$OUTPUT_DIR/merged.txt"
    log_success "Merged $# files into $OUTPUT_DIR/merged.txt"
}

# 6) deduplicate FILE
deduplicate() {
    local file="$1"
    check_file "$file" || return 1

    local original unique
    original=$(awk 'END {print NR}' "$file")
    log_info "Original lines: $original"

    awk '!seen[$0]++' "$file" > "$OUTPUT_DIR/unique.txt"

    unique=$(awk 'END {print NR}' "$OUTPUT_DIR/unique.txt")
    log_success "Unique lines: $unique"
    log_success "Duplicates removed: $((original - unique))"
    log_info "Saved to $OUTPUT_DIR/unique.txt"
}


show_menu() {
    echo "1. Count Lines"
    echo "2. Extract CSV Columns"
    echo "3. Filter Data"
    echo "4. Calculate Statistics"
    echo "5. Merge Files"
    echo "6. Remove Duplicates"
    echo "7. Check Dependencies"
    echo "8. Initialize Directories"
    echo "9. Exit"
    echo
}

main_menu() {
    local choice file columns pattern files

    while true
    do
        show_menu
        read -p "Choose an option: " choice || break

        if ! [ "$choice" -ge 0 ] 2>/dev/null; then
            log_error "Invalid option. Please enter a number between 1 and 9."
            read -p "Press Enter to continue..." _ || true
            continue
        fi
        
        case $choice in
            1)  read -p "Enter file path: " file
                count_lines "$file" || true ;;
            2)  read -p "Enter CSV file path: " file
                read -p "Enter columns (example 1,3,5): " columns
                extract_columns "$file" "$columns" || true ;;
            3)  read -p "Enter file path: " file
                read -p "Enter regex pattern: " pattern
                filter_data "$file" "$pattern" || true ;;
            4)  read -p "Enter file path (one number per line): " file
                calculate_stats "$file" || true ;;
            5)  read -p "Enter file paths separated by space: " files
                merge_files $files || true ;;
            6)  read -p "Enter file path: " file
                deduplicate "$file" || true ;;
            7)  check_dependencies || true ;;
            8)  init_directories ;;
            9)  log_info "Goodbye!"
                exit 0 ;;
            *)  log_error "Invalid choice." ;;
        esac

        echo
        read -p "Press Enter to continue..." _ || true
    done
}


init_directories
check_dependencies || exit 1
main_menu

