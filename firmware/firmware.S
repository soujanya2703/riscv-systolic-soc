.section .text
.global _start
_start:
    # Address map:
    #   0x8000_0000 = accelerator control (bit0 = load_weight)
    #   0x8000_0004 = weight register
    #   0x8000_0008 = activation register
    #   0x8000_0010 = LED / GPIO output register
    #   0x8000_0020 = result readback, PE[0][0]

    li   x1, 0x80000000      # base address of accelerator/peripheral space

    # Phase 1: turn ON load_weight
    li   x3, 1
    sw   x3, 0(x1)

    # Stream weight vector (matches original testbench: 0x0402)
    li   x3, 0x0402
    sw   x3, 4(x1)

    # Phase 2: turn OFF load_weight (freeze weights)
    li   x3, 0
    sw   x3, 0(x1)

    # Stream activation vector (matches original testbench: 0x0306)
    li   x3, 0x0306
    sw   x3, 8(x1)

    # Wait a few cycles for the systolic pipeline to settle
    li   x4, 16
delay:
    addi x4, x4, -1
    bnez x4, delay

    # Read PE[0][0] accumulation result
    lw   x5, 0x20(x1)

    # Write result's low byte out to the LED register for observability
    sw   x5, 0x10(x1)

halt:
    j halt