FUNCTION walk_dir(current_path, prefix, depth):
    IF maximum depth has been reached:
        RETURN
    END IF

    entries = get all entries inside current_path
    SORT entries in a consistent order

    FOR i = 0 TO length(entries) - 1:
        entry = entries[i]
        is_last = (i == length(entries) - 1)

        IF is_last:
            connector = "└── "
            next_prefix = prefix + "    "
        ELSE:
            connector = "├── "
            next_prefix = prefix + "│   "
        END IF

        PRINT prefix + connector + entry.name

        IF entry is a directory:
            walk_dir(entry.path, next_prefix, depth + 1)
        END IF
    END FOR
END FUNCTION

PRINT root directory name
walk_dir(root, "", 0)
