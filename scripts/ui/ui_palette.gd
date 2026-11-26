extends RefCounted
## Shared colours for the menu shell. Keep in sync with tools/build_ui_theme.gd.
##
## 0.8.7 theme contract ("black slanted" dark glass): every modal/page surface is
## one of five tokens below, every accent comes from YELLOW / CYAN / RED / BLUE,
## and every interactive plate carries a non-zero skew. Screens must not invent
## new surface colours; ask this palette for one instead.

const OUTLINE: Color = Color("1e1b3a")
const CREAM: Color = Color("fff6e3")
const INK: Color = Color("1e1b3a")
const TEXT: Color = Color("ffffff")
const TEXT_DIM: Color = Color("b9b2c9")
const MUTED: Color = Color("5a5470")
const BODY_BLUE: Color = Color("1c6d94")
const ERROR: Color = Color("c73038")
const YELLOW: Color = Color("ffd22e")
const YELLOW_DARK: Color = Color("e0a400")
const BLUE: Color = Color("45b6f0")
const BLUE_DARK: Color = Color("2a8fc4")
const RED: Color = Color("f2545b")
const RED_DARK: Color = Color("c93b44")
const PINK: Color = Color("f26ca7")
const PINK_DARK: Color = Color("c84683")
const ORANGE: Color = Color("ff922b")
const ORANGE_DARK: Color = Color("d96b0b")
const PURPLE: Color = Color("a06cff")
const CYAN: Color = Color("38d6f0")
const GRASS: Color = Color("4fbf52")
const TREE: Color = Color("3e9e44")
const SKY_TOP: Color = Color("248de0")
const SKY_BOTTOM: Color = Color("c4ecff")
const LOT: Color = Color("cbbfce")
const SURFACE_DARK: Color = Color("121528")
const SURFACE_GLASS: Color = Color(0.075, 0.082, 0.165, 0.88)
const SURFACE_CARD: Color = Color(0.110, 0.118, 0.228, 0.92)
const SURFACE_CHIP: Color = Color(0.155, 0.165, 0.305, 0.94)
const RIM_LIGHT: Color = Color(1.0, 1.0, 1.0, 0.16)

# --- 0.8.7 canonical shell tokens -----------------------------------------
const SURFACE_MODAL: Color = Color(0.056, 0.068, 0.156, 0.95) ## Slanted page / modal fill.
const MODAL_BORDER: Color = Color(0.24, 0.84, 0.96, 0.54) ## Cyan glass rim on every modal.
const MODAL_SHADE: Color = Color(0.02, 0.02, 0.08, 0.70) ## Drop shadow under a modal shell.
const SHELL_FILL: Color = Color(0.070, 0.080, 0.165, 0.96) ## Custom-drawn backdrop plate.
const SHELL_GLOSS: Color = Color(1.0, 1.0, 1.0, 0.045) ## Top glass highlight band.
const SHELL_RIM: Color = Color(0.35, 0.82, 1.0, 0.18) ## Inner cyan hairline.
const SCRIM: Color = Color(0.035, 0.043, 0.09, 0.76) ## Dim behind every modal / result card.
const SURFACE_ROW: Color = Color(0.095, 0.112, 0.228, 0.90) ## List / standings row fill.
const SURFACE_ROW_HOVER: Color = Color(0.145, 0.175, 0.335, 0.96)
const SURFACE_ROW_LOCAL: Color = Color(0.140, 0.260, 0.420, 0.94) ## "You" row.
const ROW_BORDER: Color = Color(1.0, 1.0, 1.0, 0.10) ## Hairline row outline.
const FIELD_FILL: Color = Color(0.045, 0.055, 0.125, 0.96) ## Slanted input well.
const FIELD_BORDER: Color = Color(0.28, 0.78, 0.96, 0.48)
const SURFACE_WELL: Color = Color(0.038, 0.046, 0.106, 0.82) ## Recessed list / scroll well.

