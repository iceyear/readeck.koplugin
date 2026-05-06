std = "lua51"
codes = true
max_line_length = false
exclude_files = {
    "references/**",
}

globals = {
    "G_reader_settings",
    "describe",
    "it",
    "assert",
}

ignore = {
    "611", -- line contains only whitespace
    "212/self",
}
