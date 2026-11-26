`default_nettype none
// Lab 6: WHACK-A-MOLE (VGA Playground). Uses hvsync_generator from hsync_generator.v
// top = Up/X/ui_in[0]   left = Left/Y/ui_in[1]   right = Right/A/ui_in[2]
// bottom = Down/B/ui_in[3]   start = Start/ui_in[7]
module tt_um_vga_example(
    input  wire [7:0] ui_in,  output wire [7:0] uo_out,
    input  wire [7:0] uio_in, output wire [7:0] uio_out, output wire [7:0] uio_oe,
    input  wire ena, input wire clk, input wire rst_n);

    // ---- VGA ----
    wire hsync, vsync, video_active;
    wire [9:0] x, y;
    hvsync_generator vga(.clk(clk), .reset(~rst_n), .hsync(hsync), .vsync(vsync),
                         .display_on(video_active), .hpos(x), .vpos(y));
    reg  [5:0] color;                                   // RR GG BB
    wire [5:0] c = video_active ? color : 6'd0;
    assign uo_out  = {hsync, c[0], c[2], c[4], vsync, c[1], c[3], c[5]};
    assign uio_out = 0;
    assign uio_oe  = 0;
    wire _unused = &{ena, uio_in};

    // ---- Gamepad: 12 bits arrive one by one. ui_in[4]=latch, [5]=clock, [6]=data ----
    reg [8:0]  sy  = 0;                                 // 3 samples of {data, clock, latch}
    reg [11:0] sh  = 12'hFFF, pad = 12'hFFF;
    always @(posedge clk) begin
        sy <= {sy[5:0], ui_in[6:4]};
        if (sy[4] & ~sy[7]) sh  <= {sh[10:0], sy[5]};    // clock rises: take 1 bit
        if (sy[3] & ~sy[6]) pad <= sh;                   // latch rises: all 12 bits in
    end
    wire [11:0] gp = (pad == 12'hFFF) ? 12'd0 : pad;    // {b,y,sel,start,up,down,left,right,a,x,l,r}
    wire [4:0] btn = { gp[8] | ui_in[7],                        // 4 start
                       gp[6] | gp[11] | ui_in[3],               // 3 bottom
                       gp[4] | gp[3]  | ui_in[2],               // 2 right
                       gp[5] | gp[10] | ui_in[1],               // 1 left
                       gp[7] | gp[2]  | ui_in[0] };             // 0 top

    // ---- Game state ----
    localparam [1:0] START = 0, UP = 1, DOWN = 2, OVER = 3;
    reg [1:0]  state = START, mole = 0, lives = 3;
    reg [7:0]  timer = 0;                               // in frames, 60 = 1 second
    reg [4:0]  score = 0;                               // max 31
    reg [2:0]  hits  = 0;                               // every 5 hits -> level up
    reg [3:0]  level = 0;
    reg        was_hit = 0, was_miss = 0;
    reg [5:0]  frame = 0;
    reg [15:0] lfsr  = 16'hACE1;                        // random numbers
    reg [4:0]  prev  = 0;
    wire [4:0] press = btn & ~prev;                     // 1 only on the frame a button goes down
    wire [1:0] next_hole = (lfsr[1:0] == mole) ? mole + 2'd1 : lfsr[1:0];
    wire [7:0] up_time  = 8'd90 - {4'd0, level} * 8'd7;  // 1.5 s -> 0.45 s
    wire [7:0] gap_time = 8'd40 - {4'd0, level} * 8'd3;
    wire endframe = (x == 0) && (y == 480);             // once per frame

    always @(posedge clk) begin
        if (~rst_n) begin
            state <= START; lives <= 2'd3; score <= 0;
        end else if (endframe) begin
            lfsr  <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            prev  <= btn;
            frame <= frame + 6'd1;
            case (state)
                START, OVER: if (press[4]) begin                       // new game
                    score <= 0; hits <= 0; level <= 0; lives <= 2'd3;
                    was_hit <= 0; was_miss <= 0; timer <= 8'd60; state <= DOWN;
                end
                DOWN: if (timer == 0) begin                            // mole pops up
                    mole <= next_hole; timer <= up_time;
                    was_hit <= 0; was_miss <= 0; state <= UP;
                end else timer <= timer - 8'd1;
                UP: if (press[mole]) begin                             // HIT
                    if (score != 31) score <= score + 5'd1;
                    hits <= (hits == 4) ? 3'd0 : hits + 3'd1;
                    if (hits == 4 && level != 9) level <= level + 4'd1;
                    was_hit <= 1; timer <= gap_time; state <= DOWN;
                end else if (press[3:0] != 0 || timer == 0) begin      // MISS
                    was_miss <= 1; lives <= lives - 2'd1; timer <= gap_time;
                    state <= (lives == 1) ? OVER : DOWN;
                end else timer <= timer - 8'd1;
            endcase
        end
    end

    // ---- Drawing ----
    function in_circle;   // (px-cx)^2 + (py-cy)^2 < r^2
        input [9:0] px, py, cx, cy; input [6:0] r;
        reg signed [10:0] dx, dy; reg [21:0] d2;
        begin
            dx = $signed({1'b0, px}) - $signed({1'b0, cx});
            dy = $signed({1'b0, py}) - $signed({1'b0, cy});
            d2 = dx * dx + dy * dy;
            in_circle = d2 < r * r;
        end
    endfunction
    function any_hole;    // inside any of the 4 holes, radius r
        input [9:0] px, py; input [6:0] r;
        any_hole = in_circle(px, py, 10'd320, 10'd150, r) || in_circle(px, py, 10'd170, 10'd280, r)
                || in_circle(px, py, 10'd470, 10'd280, r) || in_circle(px, py, 10'd320, 10'd400, r);
    endfunction

    wire [9:0] mx = (mole == 1) ? 10'd170 : (mole == 2) ? 10'd470 : 10'd320;   // mole's hole
    wire [9:0] my = (mole == 0) ? 10'd150 : (mole == 3) ? 10'd400 : 10'd280;
    wire show = (state == UP);
    wire ring = (state != UP) && in_circle(x, y, mx, my, 7'd60) && !in_circle(x, y, mx, my, 7'd52);
    wire [9:0] sx = x - 10'd16;                         // score / level: rows of squares
    wire score_px = (y >= 16) && (y < 32) && (x >= 16) && (sx[3:0] < 12) && (sx[9:4] < {1'b0, score});
    wire level_px = (y >= 40) && (y < 52) && (x >= 16) && (sx[3:0] < 12) && (sx[9:4] < {2'b0, level});
    wire [9:0] lx = x - 10'd540;                        // lives: up to 3 squares, top right
    wire lives_px = (y >= 20) && (y < 44) && (x >= 540) && (lx[9:5] < {3'b0, lives}) && (lx[4:0] < 24);

    always @(*) begin                                   // later lines are drawn on top
        color = (state == OVER) ? 6'b01_00_00 : 6'b00_10_00;                  // grass
        if (y < 64)                         color = 6'b00_00_01;              // top bar
        if (score_px)                       color = 6'b11_11_00;              // score
        if (level_px)                       color = 6'b11_01_00;              // level
        if (lives_px)                       color = 6'b11_00_01;              // lives
        if (ring && was_hit)                color = 6'b11_11_00;              // hit flash
        if (ring && was_miss)               color = 6'b11_00_00;              // miss flash
        if (any_hole(x, y, 7'd52))          color = 6'b01_01_00;              // dirt rim
        if (any_hole(x, y, 7'd46))          color = 6'b00_00_00;              // hole
        if (show && in_circle(x, y, mx, my - 10'd10, 7'd34)) color = 6'b10_01_00;   // mole
        if (show && in_circle(x, y, mx, my - 10'd6, 7'd7))   color = 6'b11_10_10;   // nose
        if (show && (in_circle(x, y, mx - 10'd12, my - 10'd22, 7'd5)
                  || in_circle(x, y, mx + 10'd12, my - 10'd22, 7'd5))) color = 6'b00_00_00; // eyes
        if (state != UP && state != DOWN && frame[5] && in_circle(x, y, 10'd320, 10'd280, 7'd12))
                                            color = 6'b11_11_11;              // "press start"
    end
endmodule