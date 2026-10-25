"""Build the client ZIP distributed by the BeamMP server."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(__file__).resolve().parents[1]
source = root / "ClientSource"
destination = root / "BeamMP-Roadside-Assistance-Mod" / "Client" / "BeamMP-Roadside-Assistance.zip"
destination.parent.mkdir(exist_ok=True)
with ZipFile(destination, "w", ZIP_DEFLATED) as archive:
    for path in sorted(source.rglob("*")):
        if path.is_file() and path.suffix in {".lua", ".js", ".json", ".html", ".css", ".png"}:
            archive.write(path, path.relative_to(source).as_posix())
print(destination)
