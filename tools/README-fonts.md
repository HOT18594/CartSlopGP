# UI font notes

`Fredoka.ttf` is the upstream **variable** font (wght 300-700, wdth 75-125).
Godot 4.7 does not apply the `wght` axis through `FontVariation` in this
project, so every text node would render at the 300 (Light) default.

`Fredoka-Medium.ttf` and `Fredoka-Bold.ttf` are static instances baked with
fontTools, and those are what `tools/build_ui_theme.gd` loads:

```python
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

for weight, name in [(500, "Fredoka-Medium.ttf"), (700, "Fredoka-Bold.ttf")]:
    font = TTFont("assets/ui/fonts/Fredoka.ttf")
    instantiateVariableFont(font, {"wght": weight, "wdth": 100}, inplace=True)
    font.save("assets/ui/fonts/" + name)
```

Re-run the snippet only if the upstream variable font changes. Then rebuild the
theme:

```bash
godot --headless --path . --script tools/build_ui_theme.gd
```
