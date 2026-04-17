`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      font_rom.v
// Description:
//   8×16 bitmap font ROM for VGA text rendering.
//   Stores glyphs for printable ASCII characters (0x20–0x7E).
//   Each glyph is 8 pixels wide × 16 pixels tall = 16 bytes.
//
//   Address format: { char_code[6:0], row[3:0] } = 11-bit address
//   Output: 8-bit row data, MSB = leftmost pixel
//
//   To test if pixel (col) is set: font_data[7 - col]
//
//   Synthesises to distributed RAM (LUTs) — no BRAM needed.
//   Total storage: 96 chars × 16 bytes = 1,536 bytes = 12,288 bits
//
//   Font based on the standard IBM VGA 8×16 bitmap font.
//////////////////////////////////////////////////////////////////////////////////

module font_rom (
    input      [10:0] addr,       // { char_code[6:0], row[3:0] }
    output reg [7:0]  font_data   // 8-bit pixel row (MSB = left)
);

    always @(*) begin
        case (addr)
            // ════════════════════════════════════════════════════
            // SPACE (0x20)
            // ════════════════════════════════════════════════════
            11'h200: font_data = 8'h00; 11'h201: font_data = 8'h00;
            11'h202: font_data = 8'h00; 11'h203: font_data = 8'h00;
            11'h204: font_data = 8'h00; 11'h205: font_data = 8'h00;
            11'h206: font_data = 8'h00; 11'h207: font_data = 8'h00;
            11'h208: font_data = 8'h00; 11'h209: font_data = 8'h00;
            11'h20A: font_data = 8'h00; 11'h20B: font_data = 8'h00;
            11'h20C: font_data = 8'h00; 11'h20D: font_data = 8'h00;
            11'h20E: font_data = 8'h00; 11'h20F: font_data = 8'h00;

            // ════════════════════════════════════════════════════
            // 0 (0x30)
            // ════════════════════════════════════════════════════
            11'h300: font_data = 8'h00; 11'h301: font_data = 8'h00;
            11'h302: font_data = 8'h3C; 11'h303: font_data = 8'h66;
            11'h304: font_data = 8'h66; 11'h305: font_data = 8'h66;
            11'h306: font_data = 8'h76; 11'h307: font_data = 8'h6E;
            11'h308: font_data = 8'h66; 11'h309: font_data = 8'h66;
            11'h30A: font_data = 8'h66; 11'h30B: font_data = 8'h3C;
            11'h30C: font_data = 8'h00; 11'h30D: font_data = 8'h00;
            11'h30E: font_data = 8'h00; 11'h30F: font_data = 8'h00;

            // 1 (0x31)
            11'h310: font_data = 8'h00; 11'h311: font_data = 8'h00;
            11'h312: font_data = 8'h18; 11'h313: font_data = 8'h38;
            11'h314: font_data = 8'h18; 11'h315: font_data = 8'h18;
            11'h316: font_data = 8'h18; 11'h317: font_data = 8'h18;
            11'h318: font_data = 8'h18; 11'h319: font_data = 8'h18;
            11'h31A: font_data = 8'h18; 11'h31B: font_data = 8'h7E;
            11'h31C: font_data = 8'h00; 11'h31D: font_data = 8'h00;
            11'h31E: font_data = 8'h00; 11'h31F: font_data = 8'h00;

            // 2 (0x32)
            11'h320: font_data = 8'h00; 11'h321: font_data = 8'h00;
            11'h322: font_data = 8'h3C; 11'h323: font_data = 8'h66;
            11'h324: font_data = 8'h06; 11'h325: font_data = 8'h06;
            11'h326: font_data = 8'h0C; 11'h327: font_data = 8'h18;
            11'h328: font_data = 8'h30; 11'h329: font_data = 8'h60;
            11'h32A: font_data = 8'h66; 11'h32B: font_data = 8'h7E;
            11'h32C: font_data = 8'h00; 11'h32D: font_data = 8'h00;
            11'h32E: font_data = 8'h00; 11'h32F: font_data = 8'h00;

            // 3 (0x33)
            11'h330: font_data = 8'h00; 11'h331: font_data = 8'h00;
            11'h332: font_data = 8'h3C; 11'h333: font_data = 8'h66;
            11'h334: font_data = 8'h06; 11'h335: font_data = 8'h06;
            11'h336: font_data = 8'h1C; 11'h337: font_data = 8'h06;
            11'h338: font_data = 8'h06; 11'h339: font_data = 8'h06;
            11'h33A: font_data = 8'h66; 11'h33B: font_data = 8'h3C;
            11'h33C: font_data = 8'h00; 11'h33D: font_data = 8'h00;
            11'h33E: font_data = 8'h00; 11'h33F: font_data = 8'h00;

            // 4 (0x34)
            11'h340: font_data = 8'h00; 11'h341: font_data = 8'h00;
            11'h342: font_data = 8'h0C; 11'h343: font_data = 8'h1C;
            11'h344: font_data = 8'h3C; 11'h345: font_data = 8'h6C;
            11'h346: font_data = 8'h6C; 11'h347: font_data = 8'h7E;
            11'h348: font_data = 8'h0C; 11'h349: font_data = 8'h0C;
            11'h34A: font_data = 8'h0C; 11'h34B: font_data = 8'h1E;
            11'h34C: font_data = 8'h00; 11'h34D: font_data = 8'h00;
            11'h34E: font_data = 8'h00; 11'h34F: font_data = 8'h00;

            // 5 (0x35)
            11'h350: font_data = 8'h00; 11'h351: font_data = 8'h00;
            11'h352: font_data = 8'h7E; 11'h353: font_data = 8'h60;
            11'h354: font_data = 8'h60; 11'h355: font_data = 8'h60;
            11'h356: font_data = 8'h7C; 11'h357: font_data = 8'h06;
            11'h358: font_data = 8'h06; 11'h359: font_data = 8'h06;
            11'h35A: font_data = 8'h66; 11'h35B: font_data = 8'h3C;
            11'h35C: font_data = 8'h00; 11'h35D: font_data = 8'h00;
            11'h35E: font_data = 8'h00; 11'h35F: font_data = 8'h00;

            // 6 (0x36)
            11'h360: font_data = 8'h00; 11'h361: font_data = 8'h00;
            11'h362: font_data = 8'h1C; 11'h363: font_data = 8'h30;
            11'h364: font_data = 8'h60; 11'h365: font_data = 8'h60;
            11'h366: font_data = 8'h7C; 11'h367: font_data = 8'h66;
            11'h368: font_data = 8'h66; 11'h369: font_data = 8'h66;
            11'h36A: font_data = 8'h66; 11'h36B: font_data = 8'h3C;
            11'h36C: font_data = 8'h00; 11'h36D: font_data = 8'h00;
            11'h36E: font_data = 8'h00; 11'h36F: font_data = 8'h00;

            // 7 (0x37)
            11'h370: font_data = 8'h00; 11'h371: font_data = 8'h00;
            11'h372: font_data = 8'h7E; 11'h373: font_data = 8'h66;
            11'h374: font_data = 8'h06; 11'h375: font_data = 8'h0C;
            11'h376: font_data = 8'h0C; 11'h377: font_data = 8'h18;
            11'h378: font_data = 8'h18; 11'h379: font_data = 8'h18;
            11'h37A: font_data = 8'h18; 11'h37B: font_data = 8'h18;
            11'h37C: font_data = 8'h00; 11'h37D: font_data = 8'h00;
            11'h37E: font_data = 8'h00; 11'h37F: font_data = 8'h00;

            // 8 (0x38)
            11'h380: font_data = 8'h00; 11'h381: font_data = 8'h00;
            11'h382: font_data = 8'h3C; 11'h383: font_data = 8'h66;
            11'h384: font_data = 8'h66; 11'h385: font_data = 8'h66;
            11'h386: font_data = 8'h3C; 11'h387: font_data = 8'h66;
            11'h388: font_data = 8'h66; 11'h389: font_data = 8'h66;
            11'h38A: font_data = 8'h66; 11'h38B: font_data = 8'h3C;
            11'h38C: font_data = 8'h00; 11'h38D: font_data = 8'h00;
            11'h38E: font_data = 8'h00; 11'h38F: font_data = 8'h00;

            // 9 (0x39)
            11'h390: font_data = 8'h00; 11'h391: font_data = 8'h00;
            11'h392: font_data = 8'h3C; 11'h393: font_data = 8'h66;
            11'h394: font_data = 8'h66; 11'h395: font_data = 8'h66;
            11'h396: font_data = 8'h3E; 11'h397: font_data = 8'h06;
            11'h398: font_data = 8'h06; 11'h399: font_data = 8'h06;
            11'h39A: font_data = 8'h0C; 11'h39B: font_data = 8'h38;
            11'h39C: font_data = 8'h00; 11'h39D: font_data = 8'h00;
            11'h39E: font_data = 8'h00; 11'h39F: font_data = 8'h00;

            // ════════════════════════════════════════════════════
            // : (0x3A) — colon for "SCORE: 05"
            // ════════════════════════════════════════════════════
            11'h3A0: font_data = 8'h00; 11'h3A1: font_data = 8'h00;
            11'h3A2: font_data = 8'h00; 11'h3A3: font_data = 8'h00;
            11'h3A4: font_data = 8'h18; 11'h3A5: font_data = 8'h18;
            11'h3A6: font_data = 8'h00; 11'h3A7: font_data = 8'h00;
            11'h3A8: font_data = 8'h18; 11'h3A9: font_data = 8'h18;
            11'h3AA: font_data = 8'h00; 11'h3AB: font_data = 8'h00;
            11'h3AC: font_data = 8'h00; 11'h3AD: font_data = 8'h00;
            11'h3AE: font_data = 8'h00; 11'h3AF: font_data = 8'h00;

            // ════════════════════════════════════════════════════
            // A (0x41)
            // ════════════════════════════════════════════════════
            11'h410: font_data = 8'h00; 11'h411: font_data = 8'h00;
            11'h412: font_data = 8'h18; 11'h413: font_data = 8'h3C;
            11'h414: font_data = 8'h66; 11'h415: font_data = 8'h66;
            11'h416: font_data = 8'h66; 11'h417: font_data = 8'h7E;
            11'h418: font_data = 8'h66; 11'h419: font_data = 8'h66;
            11'h41A: font_data = 8'h66; 11'h41B: font_data = 8'h66;
            11'h41C: font_data = 8'h00; 11'h41D: font_data = 8'h00;
            11'h41E: font_data = 8'h00; 11'h41F: font_data = 8'h00;

            // C (0x43)
            11'h430: font_data = 8'h00; 11'h431: font_data = 8'h00;
            11'h432: font_data = 8'h3C; 11'h433: font_data = 8'h66;
            11'h434: font_data = 8'h60; 11'h435: font_data = 8'h60;
            11'h436: font_data = 8'h60; 11'h437: font_data = 8'h60;
            11'h438: font_data = 8'h60; 11'h439: font_data = 8'h60;
            11'h43A: font_data = 8'h66; 11'h43B: font_data = 8'h3C;
            11'h43C: font_data = 8'h00; 11'h43D: font_data = 8'h00;
            11'h43E: font_data = 8'h00; 11'h43F: font_data = 8'h00;

            // D (0x44)
            11'h440: font_data = 8'h00; 11'h441: font_data = 8'h00;
            11'h442: font_data = 8'h78; 11'h443: font_data = 8'h6C;
            11'h444: font_data = 8'h66; 11'h445: font_data = 8'h66;
            11'h446: font_data = 8'h66; 11'h447: font_data = 8'h66;
            11'h448: font_data = 8'h66; 11'h449: font_data = 8'h66;
            11'h44A: font_data = 8'h6C; 11'h44B: font_data = 8'h78;
            11'h44C: font_data = 8'h00; 11'h44D: font_data = 8'h00;
            11'h44E: font_data = 8'h00; 11'h44F: font_data = 8'h00;

            // E (0x45)
            11'h450: font_data = 8'h00; 11'h451: font_data = 8'h00;
            11'h452: font_data = 8'h7E; 11'h453: font_data = 8'h60;
            11'h454: font_data = 8'h60; 11'h455: font_data = 8'h60;
            11'h456: font_data = 8'h7C; 11'h457: font_data = 8'h60;
            11'h458: font_data = 8'h60; 11'h459: font_data = 8'h60;
            11'h45A: font_data = 8'h60; 11'h45B: font_data = 8'h7E;
            11'h45C: font_data = 8'h00; 11'h45D: font_data = 8'h00;
            11'h45E: font_data = 8'h00; 11'h45F: font_data = 8'h00;

            // I (0x49)
            11'h490: font_data = 8'h00; 11'h491: font_data = 8'h00;
            11'h492: font_data = 8'h7E; 11'h493: font_data = 8'h18;
            11'h494: font_data = 8'h18; 11'h495: font_data = 8'h18;
            11'h496: font_data = 8'h18; 11'h497: font_data = 8'h18;
            11'h498: font_data = 8'h18; 11'h499: font_data = 8'h18;
            11'h49A: font_data = 8'h18; 11'h49B: font_data = 8'h7E;
            11'h49C: font_data = 8'h00; 11'h49D: font_data = 8'h00;
            11'h49E: font_data = 8'h00; 11'h49F: font_data = 8'h00;

            // L (0x4C)
            11'h4C0: font_data = 8'h00; 11'h4C1: font_data = 8'h00;
            11'h4C2: font_data = 8'h60; 11'h4C3: font_data = 8'h60;
            11'h4C4: font_data = 8'h60; 11'h4C5: font_data = 8'h60;
            11'h4C6: font_data = 8'h60; 11'h4C7: font_data = 8'h60;
            11'h4C8: font_data = 8'h60; 11'h4C9: font_data = 8'h60;
            11'h4CA: font_data = 8'h60; 11'h4CB: font_data = 8'h7E;
            11'h4CC: font_data = 8'h00; 11'h4CD: font_data = 8'h00;
            11'h4CE: font_data = 8'h00; 11'h4CF: font_data = 8'h00;

            // O (0x4F)
            11'h4F0: font_data = 8'h00; 11'h4F1: font_data = 8'h00;
            11'h4F2: font_data = 8'h3C; 11'h4F3: font_data = 8'h66;
            11'h4F4: font_data = 8'h66; 11'h4F5: font_data = 8'h66;
            11'h4F6: font_data = 8'h66; 11'h4F7: font_data = 8'h66;
            11'h4F8: font_data = 8'h66; 11'h4F9: font_data = 8'h66;
            11'h4FA: font_data = 8'h66; 11'h4FB: font_data = 8'h3C;
            11'h4FC: font_data = 8'h00; 11'h4FD: font_data = 8'h00;
            11'h4FE: font_data = 8'h00; 11'h4FF: font_data = 8'h00;
            // H (0x48)
            11'h480: font_data = 8'h00; 11'h481: font_data = 8'h00;
            11'h482: font_data = 8'h66; 11'h483: font_data = 8'h66;
            11'h484: font_data = 8'h66; 11'h485: font_data = 8'h66;
            11'h486: font_data = 8'h7E; 11'h487: font_data = 8'h66;
            11'h488: font_data = 8'h66; 11'h489: font_data = 8'h66;
            11'h48A: font_data = 8'h66; 11'h48B: font_data = 8'h66;
            11'h48C: font_data = 8'h00; 11'h48D: font_data = 8'h00;
            11'h48E: font_data = 8'h00; 11'h48F: font_data = 8'h00;

            // M (0x4D)
            11'h4D0: font_data = 8'h00; 11'h4D1: font_data = 8'h00;
            11'h4D2: font_data = 8'h63; 11'h4D3: font_data = 8'h77;
            11'h4D4: font_data = 8'h7F; 11'h4D5: font_data = 8'h6B;
            11'h4D6: font_data = 8'h63; 11'h4D7: font_data = 8'h63;
            11'h4D8: font_data = 8'h63; 11'h4D9: font_data = 8'h63;
            11'h4DA: font_data = 8'h63; 11'h4DB: font_data = 8'h63;
            11'h4DC: font_data = 8'h00; 11'h4DD: font_data = 8'h00;
            11'h4DE: font_data = 8'h00; 11'h4DF: font_data = 8'h00;
            // R (0x52)
            11'h520: font_data = 8'h00; 11'h521: font_data = 8'h00;
            11'h522: font_data = 8'h7C; 11'h523: font_data = 8'h66;
            11'h524: font_data = 8'h66; 11'h525: font_data = 8'h66;
            11'h526: font_data = 8'h7C; 11'h527: font_data = 8'h6C;
            11'h528: font_data = 8'h66; 11'h529: font_data = 8'h66;
            11'h52A: font_data = 8'h66; 11'h52B: font_data = 8'h66;
            11'h52C: font_data = 8'h00; 11'h52D: font_data = 8'h00;
            11'h52E: font_data = 8'h00; 11'h52F: font_data = 8'h00;

            // S (0x53)
            11'h530: font_data = 8'h00; 11'h531: font_data = 8'h00;
            11'h532: font_data = 8'h3C; 11'h533: font_data = 8'h66;
            11'h534: font_data = 8'h60; 11'h535: font_data = 8'h60;
            11'h536: font_data = 8'h3C; 11'h537: font_data = 8'h06;
            11'h538: font_data = 8'h06; 11'h539: font_data = 8'h06;
            11'h53A: font_data = 8'h66; 11'h53B: font_data = 8'h3C;
            11'h53C: font_data = 8'h00; 11'h53D: font_data = 8'h00;
            11'h53E: font_data = 8'h00; 11'h53F: font_data = 8'h00;

            // V (0x56)
            11'h560: font_data = 8'h00; 11'h561: font_data = 8'h00;
            11'h562: font_data = 8'h66; 11'h563: font_data = 8'h66;
            11'h564: font_data = 8'h66; 11'h565: font_data = 8'h66;
            11'h566: font_data = 8'h66; 11'h567: font_data = 8'h66;
            11'h568: font_data = 8'h66; 11'h569: font_data = 8'h3C;
            11'h56A: font_data = 8'h3C; 11'h56B: font_data = 8'h18;
            11'h56C: font_data = 8'h00; 11'h56D: font_data = 8'h00;
            11'h56E: font_data = 8'h00; 11'h56F: font_data = 8'h00;

            // X (0x58)
            11'h580: font_data = 8'h00; 11'h581: font_data = 8'h00;
            11'h582: font_data = 8'h66; 11'h583: font_data = 8'h66;
            11'h584: font_data = 8'h66; 11'h585: font_data = 8'h3C;
            11'h586: font_data = 8'h18; 11'h587: font_data = 8'h3C;
            11'h588: font_data = 8'h66; 11'h589: font_data = 8'h66;
            11'h58A: font_data = 8'h66; 11'h58B: font_data = 8'h66;
            11'h58C: font_data = 8'h00; 11'h58D: font_data = 8'h00;
            11'h58E: font_data = 8'h00; 11'h58F: font_data = 8'h00;

            // Y (0x59)
            11'h590: font_data = 8'h00; 11'h591: font_data = 8'h00;
            11'h592: font_data = 8'h66; 11'h593: font_data = 8'h66;
            11'h594: font_data = 8'h66; 11'h595: font_data = 8'h66;
            11'h596: font_data = 8'h3C; 11'h597: font_data = 8'h18;
            11'h598: font_data = 8'h18; 11'h599: font_data = 8'h18;
            11'h59A: font_data = 8'h18; 11'h59B: font_data = 8'h18;
            11'h59C: font_data = 8'h00; 11'h59D: font_data = 8'h00;
            11'h59E: font_data = 8'h00; 11'h59F: font_data = 8'h00;

            default: font_data = 8'h00;
        endcase
    end

endmodule
