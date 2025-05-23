custom_css_content = (
    """
/* Smooth animations for all transitions */
* {
    transition: all 0.2s ease !important;
}

/* Style scrollbars on websites */
::-webkit-scrollbar {
    width: 12px;
    height: 12px;
}

::-webkit-scrollbar-track {
    background: """
    + everforest["bg0"]
    + """;
    border-radius: 6px;
}

::-webkit-scrollbar-thumb {
    background: """
    + everforest["bg4"]
    + """;
    border-radius: 6px;
    border: 2px solid """
    + everforest["bg0"]
    + """;
}

::-webkit-scrollbar-thumb:hover {
    background: """
    + everforest["green"]
    + """;
}

/* Better selection colors */
::selection {
    background-color: """
    + everforest["green"]
    + """ !important;
    color: """
    + everforest["bg0"]
    + """ !important;
}

/* Rounded corners for images */
img {
    border-radius: 8px;
}

/* Better link hover effects */
a {
    text-decoration: none !important;
    border-bottom: 1px solid transparent !important;
    transition: all 0.3s ease !important;
}

a:hover {
    border-bottom: 1px solid """
    + everforest["aqua"]
    + """ !important;
}

/* Code blocks with Everforest theme */
pre, code {
    background: """
    + everforest["bg1"]
    + """ !important;
    border: 1px solid """
    + everforest["bg3"]
    + """ !important;
    border-radius: 6px !important;
    padding: 2px 6px !important;
}

/* Better buttons */
button, input[type="submit"], input[type="button"] {
    border-radius: 6px !important;
    border: 2px solid """
    + everforest["bg3"]
    + """ !important;
    background: """
    + everforest["bg2"]
    + """ !important;
    color: """
    + everforest["fg"]
    + """ !important;
    padding: 8px 16px !important;
    cursor: pointer !important;
    transition: all 0.3s ease !important;
}

button:hover, input[type="submit"]:hover, input[type="button"]:hover {
    background: """
    + everforest["green"]
    + """ !important;
    color: """
    + everforest["bg0"]
    + """ !important;
    transform: translateY(-2px) !important;
    box-shadow: 0 4px 8px rgba(0,0,0,0.3) !important;
}

/* Input fields */
input[type="text"], input[type="password"], input[type="email"], textarea {
    background: """
    + everforest["bg1"]
    + """ !important;
    border: 2px solid """
    + everforest["bg3"]
    + """ !important;
    border-radius: 6px !important;
    color: """
    + everforest["fg"]
    + """ !important;
    padding: 8px !important;
}

input:focus, textarea:focus {
    border-color: """
    + everforest["green"]
    + """ !important;
    outline: none !important;
}

/* Rounded corners for videos */
video {
    border-radius: 8px !important;
}
"""
)
