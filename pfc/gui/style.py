QSS = """
QMainWindow, QDialog, QStatusBar { background: #1b1e23; }
QWidget { font-size: 13px; }
QGroupBox {
    font-weight: 600;
    color: #c9a227;
}
QLabel#section {
    font-weight: 600;
    color: #c9a227;
    padding: 0 0 2px 0;
}
QLineEdit, QComboBox, QPlainTextEdit {
    padding: 2px 6px;
    selection-background-color: #c9a227;
    selection-color: #111;
}
QComboBox, QAbstractSpinBox, QLineEdit {
    min-height: 24px;
}
QPushButton {
    padding: 4px 10px;
    min-height: 26px;
    min-width: 64px;
    font-weight: 600;
}
QPushButton#compact {
    min-width: 28px;
    min-height: 26px;
    padding: 2px 6px;
}
QPushButton#primary {
    background: #3d4a2e;
    color: #e8edf2;
    border: 1px solid #7a9a4a;
    border-radius: 2px;
}
QPushButton#danger {
    background: #6b1f1f;
    color: #fff;
    border: 1px solid #c0392b;
    border-radius: 2px;
    min-width: 96px;
}
QPushButton#danger:hover { background: #8a2828; }
QLabel#readout {
    font-family: Menlo, Consolas, monospace;
    font-size: 13px;
    color: #e6c35c;
    background: #121417;
    border: 1px solid #3a404a;
    padding: 4px 10px;
}
QSplitter::handle { background: #3a404a; }
QScrollArea { background: transparent; border: none; }
"""
