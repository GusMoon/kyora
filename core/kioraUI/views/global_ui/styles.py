def get_minimal_scrollbar_style():
    return """
        QScrollBar:vertical {
            width: 0px;
            background: transparent;
        }
        QScrollBar:horizontal {
            height: 0px;
            background: transparent;
        }
    """
