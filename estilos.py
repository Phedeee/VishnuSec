"""
estilos.py - Aspecto visual de la aplicación.

IMPORTANTE: Windows 11 puede estar en modo oscuro. En ese caso Qt pone las letras
en blanco, y como esta app usa fondos claros, el texto quedaría invisible.
Por eso se fuerza una paleta CLARA fija (configurar_aspecto), de modo que la app
se vea igual en modo claro u oscuro.
"""
from PyQt6.QtGui import QColor, QPalette
COLOR_PRIMARIO = "#1F4E79"      # azul oscuro (el mismo del diagrama)
COLOR_FONDO = "#F4F6F9"
COLOR_TEXTO = "#1F2933"        # gris casi negro: legible sobre fondos claros

ESTILO = f"""
QWidget {{ font-size: 10.5pt; color: {COLOR_TEXTO}; }}
QDialog, QMainWindow {{ background: {COLOR_FONDO}; }}

QLabel#titulo {{ font-size: 18pt; font-weight: bold; color: {COLOR_PRIMARIO}; }}
QLabel#subtitulo {{ color: #5A6472; }}
QLabel#error {{ color: #B3261E; font-weight: bold; }}
QLabel#ok {{ color: #1B7F4B; font-weight: bold; }}

QLineEdit {{
    padding: 6px; border: 1px solid #B8C0CC; border-radius: 6px;
    background: white; color: {COLOR_TEXTO};
    selection-background-color: {COLOR_PRIMARIO}; selection-color: white;
}}
QLineEdit:focus {{ border: 2px solid {COLOR_PRIMARIO}; }}

QPushButton {{
    padding: 8px 18px; border-radius: 6px; border: 1px solid #B8C0CC;
    background: white; color: {COLOR_TEXTO};
}}
QPushButton:hover {{ background: #E6EBF2; }}
QPushButton#primario {{
    background: {COLOR_PRIMARIO}; color: white; border: none; font-weight: bold;
}}
QPushButton#primario:hover {{ background: #2A66A0; }}
QPushButton#primario:disabled {{ background: #9DB1C6; }}

QTableWidget {{
    background: white; color: {COLOR_TEXTO}; alternate-background-color: #EAF1F8;
    gridline-color: #D5DCE6; border: 1px solid #B8C0CC;
}}
QHeaderView::section {{
    background: {COLOR_PRIMARIO}; color: white; padding: 6px; border: none; font-weight: bold;
}}
QListWidget {{ background: white; border: 1px solid #B8C0CC; color: {COLOR_TEXTO}; }}
QListWidget::item {{ padding: 7px 6px; }}
QListWidget::item:selected {{ background: {COLOR_PRIMARIO}; color: white; }}
QListWidget::item:hover:!selected {{ background: #E6EBF2; }}
QPlainTextEdit {{ background: white; border: 1px solid #B8C0CC; color: {COLOR_TEXTO}; }}
QPushButton#peligro {{
    background: #B3261E; color: white; border: none; font-weight: bold;
}}
QPushButton#peligro:hover {{ background: #CC3A30; }}
QPushButton#peligro:disabled {{ background: #D9A9A5; }}
QGroupBox {{
    background: white; border: 1px solid #B8C0CC; border-radius: 6px;
    margin-top: 14px; padding: 12px; font-weight: bold;
}}
QGroupBox::title {{ subcontrol-origin: margin; left: 10px; padding: 0 6px; color: {COLOR_PRIMARIO}; }}
QComboBox {{
    padding: 5px 8px; border: 1px solid #B8C0CC; border-radius: 6px;
    background: white; color: {COLOR_TEXTO};
}}
QComboBox QAbstractItemView {{ background: white; color: {COLOR_TEXTO}; selection-background-color: {COLOR_PRIMARIO}; selection-color: white; }}
QTabWidget::pane {{ border: 1px solid #B8C0CC; background: white; }}
"""


def _paleta_clara() -> QPalette:
    """Paleta de colores claros, independiente del modo oscuro/claro de Windows."""
    p = QPalette()
    roles = {
        QPalette.ColorRole.Window: COLOR_FONDO,
        QPalette.ColorRole.WindowText: COLOR_TEXTO,
        QPalette.ColorRole.Base: "#FFFFFF",
        QPalette.ColorRole.AlternateBase: "#EAF1F8",
        QPalette.ColorRole.Text: COLOR_TEXTO,
        QPalette.ColorRole.Button: "#FFFFFF",
        QPalette.ColorRole.ButtonText: COLOR_TEXTO,
        QPalette.ColorRole.PlaceholderText: "#7B8794",
        QPalette.ColorRole.Highlight: COLOR_PRIMARIO,
        QPalette.ColorRole.HighlightedText: "#FFFFFF",
        QPalette.ColorRole.ToolTipBase: "#FFFFFF",
        QPalette.ColorRole.ToolTipText: COLOR_TEXTO,
    }
    for rol, color in roles.items():
        p.setColor(rol, QColor(color))
    return p


def configurar_aspecto(app) -> None:
    """Aplica el estilo Fusion, la paleta clara y la hoja de estilos a toda la app."""
    app.setStyle("Fusion")
    app.setPalette(_paleta_clara())
    app.setStyleSheet(ESTILO)
