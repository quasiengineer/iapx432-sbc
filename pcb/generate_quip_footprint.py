import sys

def generate_quip64_footprint(filename="3M_QUIP64.kicad_mod"):
    # The grid spacing is 1.27mm, but since pins alternate,
    # the pitch within a single sub-row is 2.54mm.
    grid_pitch = 1.27
    drill_dia = 0.8
    pad_size_x = 1.2
    pad_size_y = 1.5

    # Row Y-coordinates (from datasheet)
    row_y = {
        "Outer_Top": -12.065,   # 0.950" total span / 2
        "Inner_Top": -9.525,    # 0.750" total span / 2
        "Inner_Bottom": 9.525,
        "Outer_Bottom": 12.065
    }

    # X-axis setup: 32 columns.
    # Max X is on the right, Min X is on the left.
    x_max = (31 * grid_pitch) / 2 # 19.685mm

    body_w = 48.01
    body_h = 27.94
    pin1_chamfer_size = 1.64

    footprint_name = "Socket_QUIP_64_3M"

    kicad_mod = f"""(footprint "{footprint_name}" (layer "F.Cu")
  (tedit 0)
  (descr "3M Textool QUIP Socket, 64 Pins, 1.27mm staggered offset (2.54mm row pitch)")
  (tags "QUIP64 3M Socket")
  (attr through_hole)
  (fp_text reference "REF**" (at 0 -15) (layer "F.SilkS")
    (effects (font (size 1 1) (thickness 0.15)))
  )
  (fp_text value "3M_QUIP64_Socket" (at 0 15) (layer "F.Fab")
    (effects (font (size 1 1) (thickness 0.15)))
  )

  (fp_line (start -{body_w/2} -{body_h/2}) (end {body_w/2 - pin1_chamfer_size} -{body_h/2}) (layer "F.SilkS") (stroke (width 0.12)))
  (fp_line (start {body_w/2} {-(body_h/2) + pin1_chamfer_size}) (end {body_w/2} {body_h/2}) (layer "F.SilkS") (stroke (width 0.12)))
  (fp_line (start {body_w/2} {body_h/2}) (end -{body_w/2} {body_h/2}) (layer "F.SilkS") (stroke (width 0.12)))
  (fp_line (start -{body_w/2} {body_h/2}) (end -{body_w/2} -{body_h/2}) (layer "F.SilkS") (stroke (width 0.12)))

  (fp_line (start {body_w/2 - pin1_chamfer_size} -{body_h/2}) (end {body_w/2} {-(body_h/2) + pin1_chamfer_size}) (layer "F.SilkS") (stroke (width 0.12)))
"""

    # --- TOP SIDE (Pins 1 to 32) ---
    # Moving Right to Left
    for i in range(32):
        pin_num = i + 1
        x = x_max - (i * grid_pitch)

        # Pin 1 = Inner, Pin 2 = Outer, Pin 3 = Inner...
        if pin_num % 2 != 0:
            y = row_y["Inner_Top"]
        else:
            y = row_y["Outer_Top"]

        kicad_mod += f'  (pad "{pin_num}" thru_hole oval (at {x:.4f} {y:.4f}) (size {pad_size_x} {pad_size_y}) (drill {drill_dia}) (layers "*.Cu" "*.Mask"))\n'

    # --- BOTTOM SIDE (Pins 33 to 64) ---
    # Moving Left to Right (Counter-clockwise)
    # Pin 33 is on the far left.
    for i in range(32):
        pin_num = 33 + i
        x = -x_max + (i * grid_pitch)

        # Symmetrical check:
        # If Pin 1 (Right) is Inner, Pin 64 (Right) should be Inner.
        # Since we are moving Left to Right:
        # i=0 (Pin 33): Leftmost.
        # i=31 (Pin 64): Rightmost.
        # Pin 64 (Even) should be Inner.
        if pin_num % 2 == 0:
            y = row_y["Inner_Bottom"]
        else:
            y = row_y["Outer_Bottom"]

        kicad_mod += f'  (pad "{pin_num}" thru_hole oval (at {x:.4f} {y:.4f}) (size {pad_size_x} {pad_size_y}) (drill {drill_dia}) (layers "*.Cu" "*.Mask"))\n'

    kicad_mod += ")"

    with open(filename, "w") as f:
        f.write(kicad_mod)
    print(f"File '{filename}' generated")

if __name__ == "__main__":
    generate_quip64_footprint()