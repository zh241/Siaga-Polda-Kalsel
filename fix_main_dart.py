import os

def main():
    file_path = os.path.join('siaga_tracker', 'lib', 'main.dart')
    print("Reading", file_path)
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find the TacticalMapTab class start
    split_term = "class TacticalMapTab extends StatefulWidget {"
    if split_term not in content:
        print("Error: Split term not found!")
        return

    parts = content.split(split_term, 1)
    
    # Clean up early closing brace in parts[0]
    before_map = parts[0].rstrip()
    if before_map.endswith("}"):
        before_map = before_map[:-1].rstrip()
        print("Removed early closing brace.")
    else:
        print("Warning: Early closing brace not found at end of parts[0]!")

    # Split the map code and the rest of the file
    split_marker = "  // ============================================================================\n  // TAB MENU 3: LOGBOOK / RIWAYAT OPERASI (Image 5)"
    if split_marker not in parts[1]:
        print("Error: Split marker not found in parts[1]!")
        return

    subparts = parts[1].split(split_marker, 1)
    map_code = split_term + subparts[0]
    rest_of_file = split_marker + subparts[1]

    # Combine everything: before_map + rest_of_file + map_code
    new_content = before_map + "\n\n" + rest_of_file.rstrip() + "\n\n" + map_code.strip() + "\n"

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_content)

    print("Success: File updated successfully!")

if __name__ == '__main__':
    main()
