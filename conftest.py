"""
Configuracion raiz de pytest para el proyecto DonTolto.

Inserta la raiz del proyecto en sys.path para permitir importaciones
absolutas del tipo `engine.src.*` desde cualquier suite de pruebas.
"""

import sys
from pathlib import Path

# Garantiza que la raiz del proyecto este disponible en el path de importacion
sys.path.insert(0, str(Path(__file__).parent))
