`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module pwl_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
    localparam TOTAL_TESTS = 5; 
    localparam TIMEOUT = 10_000; 
    localparam PERIODS_TO_CHECK = 3; 
    logic clk, rst;
    logic[15:0] timer; 

    enum logic[1:0] {IDLE, TEST, CHECK, DONE} testState; 
    logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
    logic[7:0] test_num; 
    logic[7:0] testsPassed, testsFailed; 
    logic kill_tb; 
    logic panic = 0; 

    Axis_IF #(`DMA_DATA_WIDTH) pwl_dma_if(); 

    //DMA BUFFER TO SEND
    localparam BUFF_LEN_VSHORT = 2;
    logic[BUFF_LEN_VSHORT-1:0][`DMA_DATA_WIDTH-1:0] dma_buff_vshort;
    assign dma_buff_vshort = {48'h13f013f0000, 48'h1};
    //EXPECTED OUTPUT
    logic[`SPARSE_BRAM_DEPTH-1:0][`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] expected_batches_vshort;
    assign expected_batches_vshort = {0,{16'h013f, 16'h013e, 16'h013d, 16'h013c, 16'h013b, 16'h013a, 16'h0139, 16'h0138, 16'h0137, 16'h0136, 16'h0135, 16'h0134, 16'h0133, 16'h0132, 16'h0131, 16'h0130, 16'h012f, 16'h012e, 16'h012d, 16'h012c, 16'h012b, 16'h012a, 16'h0129, 16'h0128, 16'h0127, 16'h0126, 16'h0125, 16'h0124, 16'h0123, 16'h0122, 16'h0121, 16'h0120, 16'h011f, 16'h011e, 16'h011d, 16'h011c, 16'h011b, 16'h011a, 16'h0119, 16'h0118, 16'h0117, 16'h0116, 16'h0115, 16'h0114, 16'h0113, 16'h0112, 16'h0111, 16'h0110, 16'h010f, 16'h010e, 16'h010d, 16'h010c, 16'h010b, 16'h010a, 16'h0109, 16'h0108, 16'h0107, 16'h0106, 16'h0105, 16'h0104, 16'h0103, 16'h0102, 16'h0101, 16'h0100},
                                        {16'h00ff, 16'h00fe, 16'h00fd, 16'h00fc, 16'h00fb, 16'h00fa, 16'h00f9, 16'h00f8, 16'h00f7, 16'h00f6, 16'h00f5, 16'h00f4, 16'h00f3, 16'h00f2, 16'h00f1, 16'h00f0, 16'h00ef, 16'h00ee, 16'h00ed, 16'h00ec, 16'h00eb, 16'h00ea, 16'h00e9, 16'h00e8, 16'h00e7, 16'h00e6, 16'h00e5, 16'h00e4, 16'h00e3, 16'h00e2, 16'h00e1, 16'h00e0, 16'h00df, 16'h00de, 16'h00dd, 16'h00dc, 16'h00db, 16'h00da, 16'h00d9, 16'h00d8, 16'h00d7, 16'h00d6, 16'h00d5, 16'h00d4, 16'h00d3, 16'h00d2, 16'h00d1, 16'h00d0, 16'h00cf, 16'h00ce, 16'h00cd, 16'h00cc, 16'h00cb, 16'h00ca, 16'h00c9, 16'h00c8, 16'h00c7, 16'h00c6, 16'h00c5, 16'h00c4, 16'h00c3, 16'h00c2, 16'h00c1, 16'h00c0},
                                        {16'h00bf, 16'h00be, 16'h00bd, 16'h00bc, 16'h00bb, 16'h00ba, 16'h00b9, 16'h00b8, 16'h00b7, 16'h00b6, 16'h00b5, 16'h00b4, 16'h00b3, 16'h00b2, 16'h00b1, 16'h00b0, 16'h00af, 16'h00ae, 16'h00ad, 16'h00ac, 16'h00ab, 16'h00aa, 16'h00a9, 16'h00a8, 16'h00a7, 16'h00a6, 16'h00a5, 16'h00a4, 16'h00a3, 16'h00a2, 16'h00a1, 16'h00a0, 16'h009f, 16'h009e, 16'h009d, 16'h009c, 16'h009b, 16'h009a, 16'h0099, 16'h0098, 16'h0097, 16'h0096, 16'h0095, 16'h0094, 16'h0093, 16'h0092, 16'h0091, 16'h0090, 16'h008f, 16'h008e, 16'h008d, 16'h008c, 16'h008b, 16'h008a, 16'h0089, 16'h0088, 16'h0087, 16'h0086, 16'h0085, 16'h0084, 16'h0083, 16'h0082, 16'h0081, 16'h0080},
                                        {16'h007f, 16'h007e, 16'h007d, 16'h007c, 16'h007b, 16'h007a, 16'h0079, 16'h0078, 16'h0077, 16'h0076, 16'h0075, 16'h0074, 16'h0073, 16'h0072, 16'h0071, 16'h0070, 16'h006f, 16'h006e, 16'h006d, 16'h006c, 16'h006b, 16'h006a, 16'h0069, 16'h0068, 16'h0067, 16'h0066, 16'h0065, 16'h0064, 16'h0063, 16'h0062, 16'h0061, 16'h0060, 16'h005f, 16'h005e, 16'h005d, 16'h005c, 16'h005b, 16'h005a, 16'h0059, 16'h0058, 16'h0057, 16'h0056, 16'h0055, 16'h0054, 16'h0053, 16'h0052, 16'h0051, 16'h0050, 16'h004f, 16'h004e, 16'h004d, 16'h004c, 16'h004b, 16'h004a, 16'h0049, 16'h0048, 16'h0047, 16'h0046, 16'h0045, 16'h0044, 16'h0043, 16'h0042, 16'h0041, 16'h0040},
                                        {16'h003f, 16'h003e, 16'h003d, 16'h003c, 16'h003b, 16'h003a, 16'h0039, 16'h0038, 16'h0037, 16'h0036, 16'h0035, 16'h0034, 16'h0033, 16'h0032, 16'h0031, 16'h0030, 16'h002f, 16'h002e, 16'h002d, 16'h002c, 16'h002b, 16'h002a, 16'h0029, 16'h0028, 16'h0027, 16'h0026, 16'h0025, 16'h0024, 16'h0023, 16'h0022, 16'h0021, 16'h0020, 16'h001f, 16'h001e, 16'h001d, 16'h001c, 16'h001b, 16'h001a, 16'h0019, 16'h0018, 16'h0017, 16'h0016, 16'h0015, 16'h0014, 16'h0013, 16'h0012, 16'h0011, 16'h0010, 16'h000f, 16'h000e, 16'h000d, 16'h000c, 16'h000b, 16'h000a, 16'h0009, 16'h0008, 16'h0007, 16'h0006, 16'h0005, 16'h0004, 16'h0003, 16'h0002, 16'h0001, 16'h0000}};
    //FOLLOWING PATH: (time,val,slope)
    // (0, 0, 1) --> (319, 319, 0)

    //DMA BUFFER TO SEND
    localparam BUFF_LEN_SHORT = 8;
    logic[BUFF_LEN_SHORT-1:0][`DMA_DATA_WIDTH-1:0] dma_buff_short;
    assign dma_buff_short = {48'h1fe00000000, 48'h1f40014fffe, 48'hff0082ffff, 48'he600c8fffd, 48'hc1007f0002, 48'h7f00030002, 48'h400040ffff, 48'h1};
    //EXPECTED OUTPUT
    logic[`SPARSE_BRAM_DEPTH-1:0][`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] expected_batches_short;
    assign expected_batches_short = {0,{16'h0000, 16'h0000, 16'h0002, 16'h0004, 16'h0006, 16'h0008, 16'h000a, 16'h000c, 16'h000e, 16'h0010, 16'h0012, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014},
                                {16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014},
                                {16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0014, 16'h0015, 16'h0016, 16'h0017, 16'h0018, 16'h0019, 16'h001a, 16'h001b, 16'h001c, 16'h001d, 16'h001e, 16'h001f, 16'h0020, 16'h0021, 16'h0022, 16'h0023, 16'h0024, 16'h0025, 16'h0026, 16'h0027, 16'h0028, 16'h0029, 16'h002a, 16'h002b, 16'h002c, 16'h002d, 16'h002e, 16'h002f, 16'h0030, 16'h0031, 16'h0032, 16'h0033, 16'h0034, 16'h0035, 16'h0036, 16'h0037, 16'h0038, 16'h0039, 16'h003a, 16'h003b, 16'h003c, 16'h003d, 16'h003e, 16'h003f, 16'h0040, 16'h0041},
                                {16'h0042, 16'h0043, 16'h0044, 16'h0045, 16'h0046, 16'h0047, 16'h0048, 16'h0049, 16'h004a, 16'h004b, 16'h004c, 16'h004d, 16'h004e, 16'h004f, 16'h0050, 16'h0051, 16'h0052, 16'h0053, 16'h0054, 16'h0055, 16'h0056, 16'h0057, 16'h0058, 16'h0059, 16'h005a, 16'h005b, 16'h005c, 16'h005d, 16'h005e, 16'h005f, 16'h0060, 16'h0061, 16'h0062, 16'h0063, 16'h0064, 16'h0065, 16'h0066, 16'h0067, 16'h0068, 16'h0069, 16'h006a, 16'h006b, 16'h006c, 16'h006d, 16'h006e, 16'h006f, 16'h0070, 16'h0071, 16'h0072, 16'h0073, 16'h0074, 16'h0075, 16'h0076, 16'h0077, 16'h0078, 16'h0079, 16'h007a, 16'h007b, 16'h007c, 16'h007d, 16'h007e, 16'h007f, 16'h0080, 16'h0081},
                                {16'h0082, 16'h0082, 16'h0083, 16'h0086, 16'h0089, 16'h008c, 16'h008f, 16'h0092, 16'h0095, 16'h0098, 16'h009b, 16'h009e, 16'h00a1, 16'h00a4, 16'h00a7, 16'h00aa, 16'h00ad, 16'h00b0, 16'h00b3, 16'h00b6, 16'h00b9, 16'h00bc, 16'h00bf, 16'h00c2, 16'h00c5, 16'h00c8, 16'h00c7, 16'h00c5, 16'h00c3, 16'h00c1, 16'h00bf, 16'h00bd, 16'h00bb, 16'h00b9, 16'h00b7, 16'h00b5, 16'h00b3, 16'h00b1, 16'h00af, 16'h00ad, 16'h00ab, 16'h00a9, 16'h00a7, 16'h00a5, 16'h00a3, 16'h00a1, 16'h009f, 16'h009d, 16'h009b, 16'h0099, 16'h0097, 16'h0095, 16'h0093, 16'h0091, 16'h008f, 16'h008d, 16'h008b, 16'h0089, 16'h0087, 16'h0085, 16'h0083, 16'h0081, 16'h007f, 16'h007f},
                                {16'h007f, 16'h007f, 16'h007f, 16'h007d, 16'h007b, 16'h0079, 16'h0077, 16'h0075, 16'h0073, 16'h0071, 16'h006f, 16'h006d, 16'h006b, 16'h0069, 16'h0067, 16'h0065, 16'h0063, 16'h0061, 16'h005f, 16'h005d, 16'h005b, 16'h0059, 16'h0057, 16'h0055, 16'h0053, 16'h0051, 16'h004f, 16'h004d, 16'h004b, 16'h0049, 16'h0047, 16'h0045, 16'h0043, 16'h0041, 16'h003f, 16'h003d, 16'h003b, 16'h0039, 16'h0037, 16'h0035, 16'h0033, 16'h0031, 16'h002f, 16'h002d, 16'h002b, 16'h0029, 16'h0027, 16'h0025, 16'h0023, 16'h0021, 16'h001f, 16'h001d, 16'h001b, 16'h0019, 16'h0017, 16'h0015, 16'h0013, 16'h0011, 16'h000f, 16'h000d, 16'h000b, 16'h0009, 16'h0007, 16'h0005},
                                {16'h0003, 16'h0003, 16'h0003, 16'h0004, 16'h0005, 16'h0006, 16'h0007, 16'h0008, 16'h0009, 16'h000a, 16'h000b, 16'h000c, 16'h000d, 16'h000e, 16'h000f, 16'h0010, 16'h0011, 16'h0012, 16'h0013, 16'h0014, 16'h0015, 16'h0016, 16'h0017, 16'h0018, 16'h0019, 16'h001a, 16'h001b, 16'h001c, 16'h001d, 16'h001e, 16'h001f, 16'h0020, 16'h0021, 16'h0022, 16'h0023, 16'h0024, 16'h0025, 16'h0026, 16'h0027, 16'h0028, 16'h0029, 16'h002a, 16'h002b, 16'h002c, 16'h002d, 16'h002e, 16'h002f, 16'h0030, 16'h0031, 16'h0032, 16'h0033, 16'h0034, 16'h0035, 16'h0036, 16'h0037, 16'h0038, 16'h0039, 16'h003a, 16'h003b, 16'h003c, 16'h003d, 16'h003e, 16'h003f, 16'h0040},
                                {16'h003f, 16'h003e, 16'h003d, 16'h003c, 16'h003b, 16'h003a, 16'h0039, 16'h0038, 16'h0037, 16'h0036, 16'h0035, 16'h0034, 16'h0033, 16'h0032, 16'h0031, 16'h0030, 16'h002f, 16'h002e, 16'h002d, 16'h002c, 16'h002b, 16'h002a, 16'h0029, 16'h0028, 16'h0027, 16'h0026, 16'h0025, 16'h0024, 16'h0023, 16'h0022, 16'h0021, 16'h0020, 16'h001f, 16'h001e, 16'h001d, 16'h001c, 16'h001b, 16'h001a, 16'h0019, 16'h0018, 16'h0017, 16'h0016, 16'h0015, 16'h0014, 16'h0013, 16'h0012, 16'h0011, 16'h0010, 16'h000f, 16'h000e, 16'h000d, 16'h000c, 16'h000b, 16'h000a, 16'h0009, 16'h0008, 16'h0007, 16'h0006, 16'h0005, 16'h0004, 16'h0003, 16'h0002, 16'h0001, 16'h0000}};
    // FOLLOWING PATH: (time,val,slope)
    // (0, 0, 1) --> (64, 64, -1) --> (127, 3, 2) --> (193, 127, 2) --> (230, 200, -3) --> (255, 130, -1)
    // (500, 20, -2) --> (510, 0, 0)
    
    //DMA BUFFER TO SEND
    localparam BUFF_LEN_LONG = 30;
    logic[BUFF_LEN_LONG-1:0][`DMA_DATA_WIDTH-1:0] dma_buff_long, dma_buff;
    assign dma_buff_long = {48'h5e916b30000, 48'h57515c10002, 48'h57430c2e4ff, 48'h51b271d001c, 48'h4e0184d0040, 48'h4df2810f03d, 48'h4662faffff0, 48'h43a352bffe0, 48'h3f10da6008b, 48'h3f003040aa2, 48'h3b13dd0ff11, 48'h38e3a8a0018, 48'h35d13e000ca, 48'h34f1424fffb, 48'h31e020f005e, 48'h2970386fffd, 48'h29620b5e2d1, 48'h24d10520039, 48'h2432cf1fd23, 48'h20d1b600053, 48'h1bb35f0ffad, 48'h1b835c00010, 48'h15412a0005a, 48'h11d3afbff44, 48'h11c1cd21e29, 48'hf23c75ff3f, 48'h9c3be30002, 48'h8505a2025c, 48'h191940ffd2, 48'h103};
    //EXPECTED OUTPUT
    logic[`SPARSE_BRAM_DEPTH-1:0][`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] expected_batches_long;
    assign expected_batches_long = {0,{16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16b3, 16'h16a7, 16'h16a5, 16'h16a3, 16'h16a1, 16'h169f, 16'h169d, 16'h169b, 16'h1699, 16'h1697, 16'h1695, 16'h1693, 16'h1691, 16'h168f, 16'h168d, 16'h168b, 16'h1689, 16'h1687, 16'h1685, 16'h1683, 16'h1681, 16'h167f, 16'h167d, 16'h167b, 16'h1679, 16'h1677, 16'h1675, 16'h1673, 16'h1671, 16'h166f, 16'h166d, 16'h166b, 16'h1669, 16'h1667, 16'h1665, 16'h1663, 16'h1661, 16'h165f, 16'h165d, 16'h165b, 16'h1659, 16'h1657},
                                      {16'h1655, 16'h1653, 16'h1651, 16'h164f, 16'h164d, 16'h164b, 16'h1649, 16'h1647, 16'h1645, 16'h1643, 16'h1641, 16'h163f, 16'h163d, 16'h163b, 16'h1639, 16'h1637, 16'h1635, 16'h1633, 16'h1631, 16'h162f, 16'h162d, 16'h162b, 16'h1629, 16'h1627, 16'h1625, 16'h1623, 16'h1621, 16'h161f, 16'h161d, 16'h161b, 16'h1619, 16'h1617, 16'h1615, 16'h1613, 16'h1611, 16'h160f, 16'h160d, 16'h160b, 16'h1609, 16'h1607, 16'h1605, 16'h1603, 16'h1601, 16'h15ff, 16'h15fd, 16'h15fb, 16'h15f9, 16'h15f7, 16'h15f5, 16'h15f3, 16'h15f1, 16'h15ef, 16'h15ed, 16'h15eb, 16'h15e9, 16'h15e7, 16'h15e5, 16'h15e3, 16'h15e1, 16'h15df, 16'h15dd, 16'h15db, 16'h15d9, 16'h15d7},
                                      {16'h15d5, 16'h15d3, 16'h15d1, 16'h15cf, 16'h15cd, 16'h15cb, 16'h15c9, 16'h15c7, 16'h15c5, 16'h15c3, 16'h15c1, 16'h30c2, 16'h30bd, 16'h30a1, 16'h3085, 16'h3069, 16'h304d, 16'h3031, 16'h3015, 16'h2ff9, 16'h2fdd, 16'h2fc1, 16'h2fa5, 16'h2f89, 16'h2f6d, 16'h2f51, 16'h2f35, 16'h2f19, 16'h2efd, 16'h2ee1, 16'h2ec5, 16'h2ea9, 16'h2e8d, 16'h2e71, 16'h2e55, 16'h2e39, 16'h2e1d, 16'h2e01, 16'h2de5, 16'h2dc9, 16'h2dad, 16'h2d91, 16'h2d75, 16'h2d59, 16'h2d3d, 16'h2d21, 16'h2d05, 16'h2ce9, 16'h2ccd, 16'h2cb1, 16'h2c95, 16'h2c79, 16'h2c5d, 16'h2c41, 16'h2c25, 16'h2c09, 16'h2bed, 16'h2bd1, 16'h2bb5, 16'h2b99, 16'h2b7d, 16'h2b61, 16'h2b45, 16'h2b29},
                                      {16'h2b0d, 16'h2af1, 16'h2ad5, 16'h2ab9, 16'h2a9d, 16'h2a81, 16'h2a65, 16'h2a49, 16'h2a2d, 16'h2a11, 16'h29f5, 16'h29d9, 16'h29bd, 16'h29a1, 16'h2985, 16'h2969, 16'h294d, 16'h2931, 16'h2915, 16'h28f9, 16'h28dd, 16'h28c1, 16'h28a5, 16'h2889, 16'h286d, 16'h2851, 16'h2835, 16'h2819, 16'h27fd, 16'h27e1, 16'h27c5, 16'h27a9, 16'h278d, 16'h2771, 16'h2755, 16'h2739, 16'h271d, 16'h26cd, 16'h268d, 16'h264d, 16'h260d, 16'h25cd, 16'h258d, 16'h254d, 16'h250d, 16'h24cd, 16'h248d, 16'h244d, 16'h240d, 16'h23cd, 16'h238d, 16'h234d, 16'h230d, 16'h22cd, 16'h228d, 16'h224d, 16'h220d, 16'h21cd, 16'h218d, 16'h214d, 16'h210d, 16'h20cd, 16'h208d, 16'h204d},
                                      {16'h200d, 16'h1fcd, 16'h1f8d, 16'h1f4d, 16'h1f0d, 16'h1ecd, 16'h1e8d, 16'h1e4d, 16'h1e0d, 16'h1dcd, 16'h1d8d, 16'h1d4d, 16'h1d0d, 16'h1ccd, 16'h1c8d, 16'h1c4d, 16'h1c0d, 16'h1bcd, 16'h1b8d, 16'h1b4d, 16'h1b0d, 16'h1acd, 16'h1a8d, 16'h1a4d, 16'h1a0d, 16'h19cd, 16'h198d, 16'h194d, 16'h190d, 16'h18cd, 16'h188d, 16'h184d, 16'h2810, 16'h282f, 16'h283f, 16'h284f, 16'h285f, 16'h286f, 16'h287f, 16'h288f, 16'h289f, 16'h28af, 16'h28bf, 16'h28cf, 16'h28df, 16'h28ef, 16'h28ff, 16'h290f, 16'h291f, 16'h292f, 16'h293f, 16'h294f, 16'h295f, 16'h296f, 16'h297f, 16'h298f, 16'h299f, 16'h29af, 16'h29bf, 16'h29cf, 16'h29df, 16'h29ef, 16'h29ff, 16'h2a0f},
                                      {16'h2a1f, 16'h2a2f, 16'h2a3f, 16'h2a4f, 16'h2a5f, 16'h2a6f, 16'h2a7f, 16'h2a8f, 16'h2a9f, 16'h2aaf, 16'h2abf, 16'h2acf, 16'h2adf, 16'h2aef, 16'h2aff, 16'h2b0f, 16'h2b1f, 16'h2b2f, 16'h2b3f, 16'h2b4f, 16'h2b5f, 16'h2b6f, 16'h2b7f, 16'h2b8f, 16'h2b9f, 16'h2baf, 16'h2bbf, 16'h2bcf, 16'h2bdf, 16'h2bef, 16'h2bff, 16'h2c0f, 16'h2c1f, 16'h2c2f, 16'h2c3f, 16'h2c4f, 16'h2c5f, 16'h2c6f, 16'h2c7f, 16'h2c8f, 16'h2c9f, 16'h2caf, 16'h2cbf, 16'h2ccf, 16'h2cdf, 16'h2cef, 16'h2cff, 16'h2d0f, 16'h2d1f, 16'h2d2f, 16'h2d3f, 16'h2d4f, 16'h2d5f, 16'h2d6f, 16'h2d7f, 16'h2d8f, 16'h2d9f, 16'h2daf, 16'h2dbf, 16'h2dcf, 16'h2ddf, 16'h2def, 16'h2dff, 16'h2e0f},
                                      {16'h2e1f, 16'h2e2f, 16'h2e3f, 16'h2e4f, 16'h2e5f, 16'h2e6f, 16'h2e7f, 16'h2e8f, 16'h2e9f, 16'h2eaf, 16'h2ebf, 16'h2ecf, 16'h2edf, 16'h2eef, 16'h2eff, 16'h2f0f, 16'h2f1f, 16'h2f2f, 16'h2f3f, 16'h2f4f, 16'h2f5f, 16'h2f6f, 16'h2f7f, 16'h2f8f, 16'h2f9f, 16'h2faf, 16'h2fcb, 16'h2feb, 16'h300b, 16'h302b, 16'h304b, 16'h306b, 16'h308b, 16'h30ab, 16'h30cb, 16'h30eb, 16'h310b, 16'h312b, 16'h314b, 16'h316b, 16'h318b, 16'h31ab, 16'h31cb, 16'h31eb, 16'h320b, 16'h322b, 16'h324b, 16'h326b, 16'h328b, 16'h32ab, 16'h32cb, 16'h32eb, 16'h330b, 16'h332b, 16'h334b, 16'h336b, 16'h338b, 16'h33ab, 16'h33cb, 16'h33eb, 16'h340b, 16'h342b, 16'h344b, 16'h346b},
                                      {16'h348b, 16'h34ab, 16'h34cb, 16'h34eb, 16'h350b, 16'h352b, 16'h34be, 16'h3433, 16'h33a8, 16'h331d, 16'h3292, 16'h3207, 16'h317c, 16'h30f1, 16'h3066, 16'h2fdb, 16'h2f50, 16'h2ec5, 16'h2e3a, 16'h2daf, 16'h2d24, 16'h2c99, 16'h2c0e, 16'h2b83, 16'h2af8, 16'h2a6d, 16'h29e2, 16'h2957, 16'h28cc, 16'h2841, 16'h27b6, 16'h272b, 16'h26a0, 16'h2615, 16'h258a, 16'h24ff, 16'h2474, 16'h23e9, 16'h235e, 16'h22d3, 16'h2248, 16'h21bd, 16'h2132, 16'h20a7, 16'h201c, 16'h1f91, 16'h1f06, 16'h1e7b, 16'h1df0, 16'h1d65, 16'h1cda, 16'h1c4f, 16'h1bc4, 16'h1b39, 16'h1aae, 16'h1a23, 16'h1998, 16'h190d, 16'h1882, 16'h17f7, 16'h176c, 16'h16e1, 16'h1656, 16'h15cb},
                                      {16'h1540, 16'h14b5, 16'h142a, 16'h139f, 16'h1314, 16'h1289, 16'h11fe, 16'h1173, 16'h10e8, 16'h105d, 16'h0fd2, 16'h0f47, 16'h0ebc, 16'h0e31, 16'h0da6, 16'h0304, 16'h03ee, 16'h04dd, 16'h05cc, 16'h06bb, 16'h07aa, 16'h0899, 16'h0988, 16'h0a77, 16'h0b66, 16'h0c55, 16'h0d44, 16'h0e33, 16'h0f22, 16'h1011, 16'h1100, 16'h11ef, 16'h12de, 16'h13cd, 16'h14bc, 16'h15ab, 16'h169a, 16'h1789, 16'h1878, 16'h1967, 16'h1a56, 16'h1b45, 16'h1c34, 16'h1d23, 16'h1e12, 16'h1f01, 16'h1ff0, 16'h20df, 16'h21ce, 16'h22bd, 16'h23ac, 16'h249b, 16'h258a, 16'h2679, 16'h2768, 16'h2857, 16'h2946, 16'h2a35, 16'h2b24, 16'h2c13, 16'h2d02, 16'h2df1, 16'h2ee0, 16'h2fcf},
                                      {16'h30be, 16'h31ad, 16'h329c, 16'h338b, 16'h347a, 16'h3569, 16'h3658, 16'h3747, 16'h3836, 16'h3925, 16'h3a14, 16'h3b03, 16'h3bf2, 16'h3ce1, 16'h3dd0, 16'h3dba, 16'h3da2, 16'h3d8a, 16'h3d72, 16'h3d5a, 16'h3d42, 16'h3d2a, 16'h3d12, 16'h3cfa, 16'h3ce2, 16'h3cca, 16'h3cb2, 16'h3c9a, 16'h3c82, 16'h3c6a, 16'h3c52, 16'h3c3a, 16'h3c22, 16'h3c0a, 16'h3bf2, 16'h3bda, 16'h3bc2, 16'h3baa, 16'h3b92, 16'h3b7a, 16'h3b62, 16'h3b4a, 16'h3b32, 16'h3b1a, 16'h3b02, 16'h3aea, 16'h3ad2, 16'h3aba, 16'h3aa2, 16'h3a8a, 16'h39c0, 16'h38f6, 16'h382c, 16'h3762, 16'h3698, 16'h35ce, 16'h3504, 16'h343a, 16'h3370, 16'h32a6, 16'h31dc, 16'h3112, 16'h3048, 16'h2f7e},
                                      {16'h2eb4, 16'h2dea, 16'h2d20, 16'h2c56, 16'h2b8c, 16'h2ac2, 16'h29f8, 16'h292e, 16'h2864, 16'h279a, 16'h26d0, 16'h2606, 16'h253c, 16'h2472, 16'h23a8, 16'h22de, 16'h2214, 16'h214a, 16'h2080, 16'h1fb6, 16'h1eec, 16'h1e22, 16'h1d58, 16'h1c8e, 16'h1bc4, 16'h1afa, 16'h1a30, 16'h1966, 16'h189c, 16'h17d2, 16'h1708, 16'h163e, 16'h1574, 16'h14aa, 16'h13e0, 16'h13e3, 16'h13e8, 16'h13ed, 16'h13f2, 16'h13f7, 16'h13fc, 16'h1401, 16'h1406, 16'h140b, 16'h1410, 16'h1415, 16'h141a, 16'h141f, 16'h1424, 16'h13af, 16'h1351, 16'h12f3, 16'h1295, 16'h1237, 16'h11d9, 16'h117b, 16'h111d, 16'h10bf, 16'h1061, 16'h1003, 16'h0fa5, 16'h0f47, 16'h0ee9, 16'h0e8b},
                                      {16'h0e2d, 16'h0dcf, 16'h0d71, 16'h0d13, 16'h0cb5, 16'h0c57, 16'h0bf9, 16'h0b9b, 16'h0b3d, 16'h0adf, 16'h0a81, 16'h0a23, 16'h09c5, 16'h0967, 16'h0909, 16'h08ab, 16'h084d, 16'h07ef, 16'h0791, 16'h0733, 16'h06d5, 16'h0677, 16'h0619, 16'h05bb, 16'h055d, 16'h04ff, 16'h04a1, 16'h0443, 16'h03e5, 16'h0387, 16'h0329, 16'h02cb, 16'h026d, 16'h020f, 16'h020f, 16'h020f, 16'h020f, 16'h020f, 16'h020f, 16'h020f, 16'h020f, 16'h020f, 16'h020f, 16'h020f, 16'h0212, 16'h0215, 16'h0218, 16'h021b, 16'h021e, 16'h0221, 16'h0224, 16'h0227, 16'h022a, 16'h022d, 16'h0230, 16'h0233, 16'h0236, 16'h0239, 16'h023c, 16'h023f, 16'h0242, 16'h0245, 16'h0248, 16'h024b},
                                      {16'h024e, 16'h0251, 16'h0254, 16'h0257, 16'h025a, 16'h025d, 16'h0260, 16'h0263, 16'h0266, 16'h0269, 16'h026c, 16'h026f, 16'h0272, 16'h0275, 16'h0278, 16'h027b, 16'h027e, 16'h0281, 16'h0284, 16'h0287, 16'h028a, 16'h028d, 16'h0290, 16'h0293, 16'h0296, 16'h0299, 16'h029c, 16'h029f, 16'h02a2, 16'h02a5, 16'h02a8, 16'h02ab, 16'h02ae, 16'h02b1, 16'h02b4, 16'h02b7, 16'h02ba, 16'h02bd, 16'h02c0, 16'h02c3, 16'h02c6, 16'h02c9, 16'h02cc, 16'h02cf, 16'h02d2, 16'h02d5, 16'h02d8, 16'h02db, 16'h02de, 16'h02e1, 16'h02e4, 16'h02e7, 16'h02ea, 16'h02ed, 16'h02f0, 16'h02f3, 16'h02f6, 16'h02f9, 16'h02fc, 16'h02ff, 16'h0302, 16'h0305, 16'h0308, 16'h030b},
                                      {16'h030e, 16'h0311, 16'h0314, 16'h0317, 16'h031a, 16'h031d, 16'h0320, 16'h0323, 16'h0326, 16'h0329, 16'h032c, 16'h032f, 16'h0332, 16'h0335, 16'h0338, 16'h033b, 16'h033e, 16'h0341, 16'h0344, 16'h0347, 16'h034a, 16'h034d, 16'h0350, 16'h0353, 16'h0356, 16'h0359, 16'h035c, 16'h035f, 16'h0362, 16'h0365, 16'h0368, 16'h036b, 16'h036e, 16'h0371, 16'h0374, 16'h0377, 16'h037a, 16'h037d, 16'h0380, 16'h0383, 16'h0386, 16'h20b5, 16'h205a, 16'h2021, 16'h1fe8, 16'h1faf, 16'h1f76, 16'h1f3d, 16'h1f04, 16'h1ecb, 16'h1e92, 16'h1e59, 16'h1e20, 16'h1de7, 16'h1dae, 16'h1d75, 16'h1d3c, 16'h1d03, 16'h1cca, 16'h1c91, 16'h1c58, 16'h1c1f, 16'h1be6, 16'h1bad},
                                      {16'h1b74, 16'h1b3b, 16'h1b02, 16'h1ac9, 16'h1a90, 16'h1a57, 16'h1a1e, 16'h19e5, 16'h19ac, 16'h1973, 16'h193a, 16'h1901, 16'h18c8, 16'h188f, 16'h1856, 16'h181d, 16'h17e4, 16'h17ab, 16'h1772, 16'h1739, 16'h1700, 16'h16c7, 16'h168e, 16'h1655, 16'h161c, 16'h15e3, 16'h15aa, 16'h1571, 16'h1538, 16'h14ff, 16'h14c6, 16'h148d, 16'h1454, 16'h141b, 16'h13e2, 16'h13a9, 16'h1370, 16'h1337, 16'h12fe, 16'h12c5, 16'h128c, 16'h1253, 16'h121a, 16'h11e1, 16'h11a8, 16'h116f, 16'h1136, 16'h10fd, 16'h10c4, 16'h108b, 16'h1052, 16'h132c, 16'h1609, 16'h18e6, 16'h1bc3, 16'h1ea0, 16'h217d, 16'h245a, 16'h2737, 16'h2a14, 16'h2cf1, 16'h2c8f, 16'h2c3c, 16'h2be9},
                                      {16'h2b96, 16'h2b43, 16'h2af0, 16'h2a9d, 16'h2a4a, 16'h29f7, 16'h29a4, 16'h2951, 16'h28fe, 16'h28ab, 16'h2858, 16'h2805, 16'h27b2, 16'h275f, 16'h270c, 16'h26b9, 16'h2666, 16'h2613, 16'h25c0, 16'h256d, 16'h251a, 16'h24c7, 16'h2474, 16'h2421, 16'h23ce, 16'h237b, 16'h2328, 16'h22d5, 16'h2282, 16'h222f, 16'h21dc, 16'h2189, 16'h2136, 16'h20e3, 16'h2090, 16'h203d, 16'h1fea, 16'h1f97, 16'h1f44, 16'h1ef1, 16'h1e9e, 16'h1e4b, 16'h1df8, 16'h1da5, 16'h1d52, 16'h1cff, 16'h1cac, 16'h1c59, 16'h1c06, 16'h1bb3, 16'h1b60, 16'h1bad, 16'h1c00, 16'h1c53, 16'h1ca6, 16'h1cf9, 16'h1d4c, 16'h1d9f, 16'h1df2, 16'h1e45, 16'h1e98, 16'h1eeb, 16'h1f3e, 16'h1f91},
                                      {16'h1fe4, 16'h2037, 16'h208a, 16'h20dd, 16'h2130, 16'h2183, 16'h21d6, 16'h2229, 16'h227c, 16'h22cf, 16'h2322, 16'h2375, 16'h23c8, 16'h241b, 16'h246e, 16'h24c1, 16'h2514, 16'h2567, 16'h25ba, 16'h260d, 16'h2660, 16'h26b3, 16'h2706, 16'h2759, 16'h27ac, 16'h27ff, 16'h2852, 16'h28a5, 16'h28f8, 16'h294b, 16'h299e, 16'h29f1, 16'h2a44, 16'h2a97, 16'h2aea, 16'h2b3d, 16'h2b90, 16'h2be3, 16'h2c36, 16'h2c89, 16'h2cdc, 16'h2d2f, 16'h2d82, 16'h2dd5, 16'h2e28, 16'h2e7b, 16'h2ece, 16'h2f21, 16'h2f74, 16'h2fc7, 16'h301a, 16'h306d, 16'h30c0, 16'h3113, 16'h3166, 16'h31b9, 16'h320c, 16'h325f, 16'h32b2, 16'h3305, 16'h3358, 16'h33ab, 16'h33fe, 16'h3451},
                                      {16'h34a4, 16'h34f7, 16'h354a, 16'h359d, 16'h35f0, 16'h35e0, 16'h35d0, 16'h35c0, 16'h356e, 16'h3514, 16'h34ba, 16'h3460, 16'h3406, 16'h33ac, 16'h3352, 16'h32f8, 16'h329e, 16'h3244, 16'h31ea, 16'h3190, 16'h3136, 16'h30dc, 16'h3082, 16'h3028, 16'h2fce, 16'h2f74, 16'h2f1a, 16'h2ec0, 16'h2e66, 16'h2e0c, 16'h2db2, 16'h2d58, 16'h2cfe, 16'h2ca4, 16'h2c4a, 16'h2bf0, 16'h2b96, 16'h2b3c, 16'h2ae2, 16'h2a88, 16'h2a2e, 16'h29d4, 16'h297a, 16'h2920, 16'h28c6, 16'h286c, 16'h2812, 16'h27b8, 16'h275e, 16'h2704, 16'h26aa, 16'h2650, 16'h25f6, 16'h259c, 16'h2542, 16'h24e8, 16'h248e, 16'h2434, 16'h23da, 16'h2380, 16'h2326, 16'h22cc, 16'h2272, 16'h2218},
                                      {16'h21be, 16'h2164, 16'h210a, 16'h20b0, 16'h2056, 16'h1ffc, 16'h1fa2, 16'h1f48, 16'h1eee, 16'h1e94, 16'h1e3a, 16'h1de0, 16'h1d86, 16'h1d2c, 16'h1cd2, 16'h1c78, 16'h1c1e, 16'h1bc4, 16'h1b6a, 16'h1b10, 16'h1ab6, 16'h1a5c, 16'h1a02, 16'h19a8, 16'h194e, 16'h18f4, 16'h189a, 16'h1840, 16'h17e6, 16'h178c, 16'h1732, 16'h16d8, 16'h167e, 16'h1624, 16'h15ca, 16'h1570, 16'h1516, 16'h14bc, 16'h1462, 16'h1408, 16'h13ae, 16'h1354, 16'h12fa, 16'h12a0, 16'h1353, 16'h140f, 16'h14cb, 16'h1587, 16'h1643, 16'h16ff, 16'h17bb, 16'h1877, 16'h1933, 16'h19ef, 16'h1aab, 16'h1b67, 16'h1c23, 16'h1cdf, 16'h1d9b, 16'h1e57, 16'h1f13, 16'h1fcf, 16'h208b, 16'h2147},
                                      {16'h2203, 16'h22bf, 16'h237b, 16'h2437, 16'h24f3, 16'h25af, 16'h266b, 16'h2727, 16'h27e3, 16'h289f, 16'h295b, 16'h2a17, 16'h2ad3, 16'h2b8f, 16'h2c4b, 16'h2d07, 16'h2dc3, 16'h2e7f, 16'h2f3b, 16'h2ff7, 16'h30b3, 16'h316f, 16'h322b, 16'h32e7, 16'h33a3, 16'h345f, 16'h351b, 16'h35d7, 16'h3693, 16'h374f, 16'h380b, 16'h38c7, 16'h3983, 16'h3a3f, 16'h3afb, 16'h1cd2, 16'h1d8c, 16'h1e4d, 16'h1f0e, 16'h1fcf, 16'h2090, 16'h2151, 16'h2212, 16'h22d3, 16'h2394, 16'h2455, 16'h2516, 16'h25d7, 16'h2698, 16'h2759, 16'h281a, 16'h28db, 16'h299c, 16'h2a5d, 16'h2b1e, 16'h2bdf, 16'h2ca0, 16'h2d61, 16'h2e22, 16'h2ee3, 16'h2fa4, 16'h3065, 16'h3126, 16'h31e7},
                                      {16'h32a8, 16'h3369, 16'h342a, 16'h34eb, 16'h35ac, 16'h366d, 16'h372e, 16'h37ef, 16'h38b0, 16'h3971, 16'h3a32, 16'h3af3, 16'h3bb4, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c75, 16'h3c73, 16'h3c71, 16'h3c6f, 16'h3c6d, 16'h3c6b, 16'h3c69, 16'h3c67, 16'h3c65, 16'h3c63, 16'h3c61, 16'h3c5f, 16'h3c5d, 16'h3c5b, 16'h3c59, 16'h3c57, 16'h3c55, 16'h3c53, 16'h3c51, 16'h3c4f, 16'h3c4d, 16'h3c4b, 16'h3c49, 16'h3c47, 16'h3c45, 16'h3c43, 16'h3c41, 16'h3c3f, 16'h3c3d, 16'h3c3b, 16'h3c39, 16'h3c37, 16'h3c35, 16'h3c33, 16'h3c31, 16'h3c2f, 16'h3c2d, 16'h3c2b},
                                      {16'h3c29, 16'h3c27, 16'h3c25, 16'h3c23, 16'h3c21, 16'h3c1f, 16'h3c1d, 16'h3c1b, 16'h3c19, 16'h3c17, 16'h3c15, 16'h3c13, 16'h3c11, 16'h3c0f, 16'h3c0d, 16'h3c0b, 16'h3c09, 16'h3c07, 16'h3c05, 16'h3c03, 16'h3c01, 16'h3bff, 16'h3bfd, 16'h3bfb, 16'h3bf9, 16'h3bf7, 16'h3bf5, 16'h3bf3, 16'h3bf1, 16'h3bef, 16'h3bed, 16'h3beb, 16'h3be9, 16'h3be7, 16'h3be5, 16'h3be3, 16'h398a, 16'h372e, 16'h34d2, 16'h3276, 16'h301a, 16'h2dbe, 16'h2b62, 16'h2906, 16'h26aa, 16'h244e, 16'h21f2, 16'h1f96, 16'h1d3a, 16'h1ade, 16'h1882, 16'h1626, 16'h13ca, 16'h116e, 16'h0f12, 16'h0cb6, 16'h0a5a, 16'h07fe, 16'h05a2, 16'h0606, 16'h0634, 16'h0662, 16'h0690, 16'h06be},
                                      {16'h06ec, 16'h071a, 16'h0748, 16'h0776, 16'h07a4, 16'h07d2, 16'h0800, 16'h082e, 16'h085c, 16'h088a, 16'h08b8, 16'h08e6, 16'h0914, 16'h0942, 16'h0970, 16'h099e, 16'h09cc, 16'h09fa, 16'h0a28, 16'h0a56, 16'h0a84, 16'h0ab2, 16'h0ae0, 16'h0b0e, 16'h0b3c, 16'h0b6a, 16'h0b98, 16'h0bc6, 16'h0bf4, 16'h0c22, 16'h0c50, 16'h0c7e, 16'h0cac, 16'h0cda, 16'h0d08, 16'h0d36, 16'h0d64, 16'h0d92, 16'h0dc0, 16'h0dee, 16'h0e1c, 16'h0e4a, 16'h0e78, 16'h0ea6, 16'h0ed4, 16'h0f02, 16'h0f30, 16'h0f5e, 16'h0f8c, 16'h0fba, 16'h0fe8, 16'h1016, 16'h1044, 16'h1072, 16'h10a0, 16'h10ce, 16'h10fc, 16'h112a, 16'h1158, 16'h1186, 16'h11b4, 16'h11e2, 16'h1210, 16'h123e},
                                      {16'h126c, 16'h129a, 16'h12c8, 16'h12f6, 16'h1324, 16'h1352, 16'h1380, 16'h13ae, 16'h13dc, 16'h140a, 16'h1438, 16'h1466, 16'h1494, 16'h14c2, 16'h14f0, 16'h151e, 16'h154c, 16'h157a, 16'h15a8, 16'h15d6, 16'h1604, 16'h1632, 16'h1660, 16'h168e, 16'h16bc, 16'h16ea, 16'h1718, 16'h1746, 16'h1774, 16'h17a2, 16'h17d0, 16'h17fe, 16'h182c, 16'h185a, 16'h1888, 16'h18b6, 16'h18e4, 16'h1912, 16'h1940, 16'h1848, 16'h1745, 16'h1642, 16'h153f, 16'h143c, 16'h1339, 16'h1236, 16'h1133, 16'h1030, 16'h0f2d, 16'h0e2a, 16'h0d27, 16'h0c24, 16'h0b21, 16'h0a1e, 16'h091b, 16'h0818, 16'h0715, 16'h0612, 16'h050f, 16'h040c, 16'h0309, 16'h0206, 16'h0103, 16'h0000}};
    /*
    FOLLOWING PATH: (time,val,slope)
    (0, 0, 259) --> (25, 6464, -46) --> (133, 1442, 604) --> (156, 15331, 2) --> (242, 15477, -193) --> (284, 7378, 7721)
    (285, 15099, -188) --> (340, 4768, 90) --> (440, 13760, 16) --> (443, 13808, -83) --> (525, 7008, 83)
    (579, 11505, -733) --> (589, 4178, 57) --> (662, 8373, -7471) --> (663, 902, -3) --> (798, 527, 94)
    (847, 5156, -5) --> (861, 5088, 202) --> (910, 14986, 24) --> (945, 15824, -239) --> (1008, 772, 2722)
    (1009, 3494, 139) --> (1082, 13611, -32) --> (1126, 12207, -16) --> (1247, 10256, -4035) --> (1248, 6221, 64)
    (1307, 10013, 28) --> (1396, 12482, -6913) --> (1397, 5569, 2) --> (1513, 5811, 0)
    */
    enum logic[1:0] {IDLE_PWL, SEND_BUFF,VERIFY} pwlTestState; 
    logic[`MEM_SIZE-1:0] fresh_bits; 
    logic[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] mem_map, read_resps; 
    logic[`BATCH_WIDTH-1:0] dac_batch; 
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] dac_samples; 
    logic halt, dac0_rdy, valid_dac_batch; 
    logic[$clog2(BUFF_LEN_LONG):0] dma_i;
    logic send_dma_buff,run_pwl; 
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] curr_expected_batch; 
    logic[$clog2(`SPARSE_BRAM_DEPTH):0] exp_i; 
    logic[`BATCH_SAMPLES-1:0] error_vec; 
    logic[$clog2(BUFF_LEN_LONG):0] dma_buff_len; 
    logic checked_full_wave;
    logic[1:0] wave_to_send; 
    logic[$clog2(PERIODS_TO_CHECK):0] periods; 


    DAC_Interface DUT (.clk(clk), .rst(rst),
                       .fresh_bits(fresh_bits),
                       .read_resps(read_resps),
                       .halt(halt),
                       .dac0_rdy(dac0_rdy),
                       .dac_batch(dac_batch),
                       .valid_dac_batch(valid_dac_batch),
                       .pwl_dma_if(pwl_dma_if));
    always_comb begin
        for (int i = 0; i < `BATCH_SAMPLES; i++) begin
            dac_samples[i] = dac_batch[`SAMPLE_WIDTH*i+:`SAMPLE_WIDTH];
        end 
    end
    oscillate_sig oscillator(.clk(clk), .rst(rst), .long_on(1'b1),
                             .osc_sig_out(dac0_rdy));

    always_comb begin
        if ((test_num == 0 || test_num == 3 || test_num == 4) && pwlTestState == VERIFY && periods < PERIODS_TO_CHECK) begin
            if (valid_dac_batch) begin
                test_check = {dac_batch == curr_expected_batch,1'b1};
                for (int i = 0; i < `BATCH_WIDTH; i++) error_vec[i] = ~(dac_samples[i] == curr_expected_batch[i]); 
            end else {test_check,error_vec} = 0;
        end else if (test_num == 1 && halt) begin
            test_check = {~valid_dac_batch,~valid_dac_batch && dac0_rdy};
            error_vec = 0; 
        end
        else {test_check,error_vec} = 0; 
    end

    always_ff @(posedge clk) begin
        if (rst || panic) begin
            if (panic) begin
                testState <= DONE;
                kill_tb <= 1; 
                panic <= 0;
            end else begin
                testState <= IDLE;
                {test_num,testsPassed,testsFailed, kill_tb} <= 0; 
                {done,timer} <= 0;

                pwlTestState <= IDLE_PWL;
                {send_dma_buff,run_pwl,dma_i,exp_i,periods} <= 0;
                {pwl_dma_if.last, pwl_dma_if.data, pwl_dma_if.valid} <= 0;
                {fresh_bits, halt, mem_map, read_resps} <= 0; 
                wave_to_send <= 1; 
            end
        end else begin
            case(testState)
                IDLE: begin 
                    if (start) testState <= TEST; 
                    if (done) done <= 0; 
                end 
                TEST: begin
                   
                end 
                CHECK: begin
                    if (test_num == 3) begin
                        if (timer == 20) begin
                            test_num <= test_num + 1;
                            timer <= 0;
                            if (test_num >= TOTAL_TESTS-1) testState <= DONE;
                            else testState <= TEST;
                        end else timer <= timer + 1; 
                    end else begin 
                        test_num <= test_num + 1;
                        if (test_num >= TOTAL_TESTS-1) testState <= DONE;
                        else testState <= TEST;        
                    end        
                end 

                DONE: begin 
                    done <= {testsFailed == 0 && ~kill_tb,1'b1}; 
                    testState <= IDLE; 
                    test_num <= 0; 
                end 
            endcase

            if (test_num == 0 || test_num == 3 || test_num == 4) begin
                if (test_check[0]) begin
                    if (test_check[1]) begin 
                        testsPassed <= testsPassed + 1;
                        if (VERBOSE) $write("%c[1;32m",27); 
                        if (VERBOSE) $write("t%0d_%0d+ ",test_num,exp_i);
                        if (VERBOSE) $write("%c[0m",27); 
                    end 
                    else begin 
                        testsFailed <= testsFailed + 1; 
                        if (VERBOSE) $write("%c[1;31m",27); 
                        if (VERBOSE) $write("t%0d_%0d- ",test_num,exp_i);
                        if (VERBOSE) $write("%c[0m",27); 
                    end 
                    if (VERBOSE && checked_full_wave) $write("\nChecked period #%0d\n",periods+1);
                end 
            end else begin
                if (test_check[0]) begin
                    if (test_check[1]) begin 
                        testsPassed <= testsPassed + 1;
                        if (VERBOSE) $write("%c[1;32m",27); 
                        if (VERBOSE) $write("t%0d+ ",test_num);
                        if (VERBOSE) $write("%c[0m",27); 
                    end 
                    else begin 
                        testsFailed <= testsFailed + 1; 
                        if (VERBOSE) $write("%c[1;31m",27); 
                        if (VERBOSE) $write("t%0d- ",test_num);
                        if (VERBOSE) $write("%c[0m",27); 
                    end 
                end 
            end

        end
    end

    logic[1:0] testNum_edge;
    enum logic {WATCH, PANIC} panicState; 
    logic go; 
    logic[$clog2(TIMEOUT):0] timeout_cntr; 
    edetect #(.DATA_WIDTH(8))
    testNum_edetect (.clk(clk), .rst(rst),
                     .val(test_num),
                     .comb_posedge_out(testNum_edge));  

    always_ff @(posedge clk) begin 
        if (rst) begin 
            {timeout_cntr,panic} <= 0;
            panicState <= WATCH;
            if (start) go <= 1; 
            else go <= 0; 
        end 
        else begin
            if (start) go <= 1;
            if (go) begin
                case(panicState) 
                    WATCH: begin
                        if (timeout_cntr <= TIMEOUT) begin
                            if (testNum_edge == 1) timeout_cntr <= 0;
                            else timeout_cntr <= timeout_cntr + 1;
                        end else begin
                            panic <= 1; 
                            panicState <= PANIC; 
                        end 
                    end 
                    PANIC: if (panic) panic <= 0; 
                endcase
            end 
        end
    end 

    always begin
        #5;  
        clk = !clk;
    end
     
    initial begin
        clk = 0;
        rst = 0; 
        `flash_sig(rst); 
        while (~start) #1; 
        if (VERBOSE) $display("\n############ Starting PWL Tests ############");
        #100;
        while (testState != DONE && timeout_cntr < TIMEOUT) #10;
        if (timeout_cntr < TIMEOUT) begin
            if (testsFailed != 0) begin 
                if (VERBOSE) $write("%c[1;31m",27); 
                if (VERBOSE) $display("\nPWL Tests Failed :((\n");
                if (VERBOSE) $write("%c[0m",27);
            end else begin 
                if (VERBOSE) $write("%c[1;32m",27); 
                if (VERBOSE) $display("\nPWL Tests Passed :))\n");
                if (VERBOSE) $write("%c[0m",27); 
            end
            #100;
        end else begin
            $write("%c[1;31m",27); 
            $display("\nPWL Tests Timed out on test %d!\n", test_num);
            $write("%c[0m",27);
            #100; 
        end
    end 

endmodule 

`default_nettype wire
