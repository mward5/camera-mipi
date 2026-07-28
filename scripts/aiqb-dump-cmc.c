/*
 * Phase 1 extractor for docs/aiqb-iq-tuning-scoping.md.
 *
 * Links Intel's own ia_cmc_parser and prints the parsed colour-matrix
 * (CCM) table out of a .aiqb blob -- no format reverse-engineering of
 * the *data*, just calling the vendor's parser and walking the structs
 * it hands back.
 *
 * One real container-framing fact was needed to get here: the .aiqb
 * file on disk is a "CPFF"-wrapped envelope (magic/size/checksum) that
 * itself contains named sub-blocks ("LCMC", "DFLT", "AIQB", ...).
 * ia_cmc_parser_init_v1() does not understand that outer envelope --
 * feeding it the whole file makes it misread the "LCMC" tag bytes as
 * a bogus record size and segfault reading past the buffer. The parser
 * wants the *inner* "AIQB"-tagged sub-blob (itself framed the same way:
 * magic + size + reserved + checksum), which is what this tool locates
 * and hands over. That's container framing, not payload decoding --
 * the payload itself (the CCM tables, light sources, etc.) is entirely
 * produced by Intel's parser.
 *
 * Build: see scripts/aiqb-dump-cmc-build.sh
 * Usage: aiqb-dump-cmc <path-to.aiqb> [nvm-blob]
 */

#include <ia_cmc_parser.h>
#include <ia_cmc_types.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *light_source_name(cmc_light_source ls)
{
    switch (ls) {
    case cmc_light_source_none:  return "none";
    case cmc_light_source_a:     return "A (incandescent/tungsten)";
    case cmc_light_source_b:     return "B (obsolete: noon sunlight)";
    case cmc_light_source_c:     return "C (obsolete: north sky daylight)";
    case cmc_light_source_d50:   return "D50 (horizon light)";
    case cmc_light_source_d55:   return "D55 (mid-morning/afternoon daylight)";
    case cmc_light_source_d65:   return "D65 (noon daylight, sRGB)";
    case cmc_light_source_d75:   return "D75 (north sky daylight)";
    case cmc_light_source_e:     return "E (equal energy)";
    case cmc_light_source_f1:    return "F1 (daylight fluorescent)";
    case cmc_light_source_f2:    return "F2 (cool white fluorescent)";
    case cmc_light_source_f3:    return "F3 (white fluorescent)";
    case cmc_light_source_f4:    return "F4 (warm white fluorescent)";
    case cmc_light_source_f5:    return "F5 (daylight fluorescent)";
    case cmc_light_source_f6:    return "F6 (lite white fluorescent)";
    case cmc_light_source_f7:    return "F7 (D65 simulator)";
    case cmc_light_source_f8:    return "F8 (D50 simulator)";
    case cmc_light_source_f9:    return "F9 (cool white deluxe fluorescent)";
    case cmc_light_source_f10:   return "F10 (Philips TL85)";
    case cmc_light_source_f11:   return "F11 (Philips TL84)";
    case cmc_light_source_f12:   return "F12 (Philips TL83)";
    case cmc_light_source_hz:    return "Hz (horizon IR)";
    case cmc_light_source_a_md:  return "A-medium (incandescent, medium)";
    case cmc_light_source_a_lw:  return "A-low (incandescent, low)";
    default:                     return "?";
    }
}

static void print_float_matrix(const float m[9])
{
    for (int r = 0; r < 3; r++) {
        double row_sum = (double)m[r * 3 + 0] + m[r * 3 + 1] + m[r * 3 + 2];
        printf("      [ %8.4f %8.4f %8.4f ]  row_sum=%.4f\n",
               m[r * 3 + 0], m[r * 3 + 1], m[r * 3 + 2], row_sum);
    }
}

static ia_binary_data read_file_as_binary_data(const char *path)
{
    ia_binary_data bd = { NULL, 0 };

    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "error: cannot open '%s': %s\n", path, strerror(errno));
        return bd;
    }

    if (fseek(f, 0, SEEK_END) != 0 || ftell(f) < 0) {
        fprintf(stderr, "error: cannot size '%s'\n", path);
        fclose(f);
        return bd;
    }
    long size = ftell(f);
    rewind(f);

    void *buf = malloc((size_t)size);
    if (!buf) {
        fprintf(stderr, "error: out of memory reading '%s' (%ld bytes)\n", path, size);
        fclose(f);
        return bd;
    }

    if (fread(buf, 1, (size_t)size, f) != (size_t)size) {
        fprintf(stderr, "error: short read on '%s'\n", path);
        free(buf);
        fclose(f);
        return bd;
    }
    fclose(f);

    bd.data = buf;
    bd.size = (unsigned int)size;
    return bd;
}

/* The .aiqb file on disk is "CPFF"-wrapped; find the inner "AIQB"-tagged
 * sub-blob that ia_cmc_parser_init_v1() actually understands. Its header
 * is [magic("AIQB") u32][size u32][12 reserved bytes][checksum u32]...,
 * mirroring the outer CPFF envelope's own shape. */
static int find_inner_aiqb_blob(const ia_binary_data *file, ia_binary_data *out)
{
    const unsigned char *data = file->data;
    int have_fallback = 0;
    unsigned int fallback_offset = 0, fallback_size = 0;

    for (unsigned int i = 0; i + 8 <= file->size; i++) {
        if (memcmp(data + i, "AIQB", 4) != 0)
            continue;

        unsigned int inner_size;
        memcpy(&inner_size, data + i + 4, 4);
        if ((unsigned long)i + inner_size > file->size)
            continue; /* declared size doesn't fit -- not the real tag */

        /* Per this function's own header-layout comment, the 12 bytes
         * after the size field are reserved. Every real header seen so
         * far (all six of Dell's own s5k3j1/hi556 .aiqb files) is
         * all-zero there; a match with nonzero bytes there is more
         * likely an incidental "AIQB" byte sequence inside a preceding
         * sub-block's opaque payload than the real directory entry.
         * Prefer an all-zero match over the first size-fits match. */
        if (i + 20 <= file->size) {
            int reserved_zero = 1;
            for (int r = 0; r < 12; r++) {
                if (data[i + 8 + r] != 0) {
                    reserved_zero = 0;
                    break;
                }
            }
            if (reserved_zero) {
                out->data = (void *)(data + i);
                out->size = inner_size;
                return 1;
            }
        }
        if (!have_fallback) {
            have_fallback = 1;
            fallback_offset = i;
            fallback_size = inner_size;
        }
    }

    if (have_fallback) {
        fprintf(stderr,
                "warning: \"AIQB\" match at offset %u has nonzero (or "
                "unreadable) reserved bytes -- using it anyway since no "
                "cleaner match was found, but this could be an incidental "
                "byte match rather than the real directory entry\n",
                fallback_offset);
        out->data = (void *)(data + fallback_offset);
        out->size = fallback_size;
        return 1;
    }

    return 0;
}

/* Emits a ready-to-paste libcamera soft-ISP `Ccm:` yaml block: one
 * { ct, ccm } node per light source, using the hue-averaged
 * traditional_color_matrix (the soft ISP's Ccm algorithm keys purely on
 * colour temperature, not hue, so the per-sector detail doesn't apply
 * here). Matrix::readYaml expects a flat 9-value row-major list, matching
 * cmc_acm_color_matrix_t::color_matrix exactly -- no reordering needed. */
static void print_yaml_ccm(const cmc_parsed_advanced_color_matrix_t *acm)
{
    printf("  - Ccm:\n      ccms:\n");
    uint16_t n = acm->cmc_advanced_color_matrix_info->light_sources_count;
    for (uint16_t i = 0; i < n; i++) {
        const cmc_parsed_advanced_color_matrices_ls_t *ls = &acm->cmc_parsed_advanced_color_matrices_ls[i];
        if (!ls->color_matrices_info) continue;
        const float *m = ls->traditional_color_matrix.color_matrix;
        printf("        - ct: %u\n", ls->color_matrices_info->cct);
        printf("          ccm: [ %.6f, %.6f, %.6f,\n", m[0], m[1], m[2]);
        printf("                 %.6f, %.6f, %.6f,\n", m[3], m[4], m[5]);
        printf("                 %.6f, %.6f, %.6f]\n", m[6], m[7], m[8]);
    }
}

int main(int argc, char **argv)
{
    int yaml_mode = 0;
    int argi = 1;
    if (argi < argc && strcmp(argv[argi], "--yaml") == 0) {
        yaml_mode = 1;
        argi++;
    }
    int nargs = argc - argi;
    if (nargs < 1 || nargs > 2) {
        fprintf(stderr, "usage: %s [--yaml] <path-to.aiqb> [nvm-blob]\n", argv[0]);
        return 2;
    }
    char *path_arg = argv[argi];
    char *nvm_arg = (nargs == 2) ? argv[argi + 1] : NULL;

    ia_binary_data file = read_file_as_binary_data(path_arg);
    if (!file.data)
        return 1;

    ia_binary_data aiqb;
    if (!find_inner_aiqb_blob(&file, &aiqb)) {
        fprintf(stderr, "error: no inner \"AIQB\" sub-blob found in '%s'\n", path_arg);
        free(file.data);
        return 1;
    }

    ia_binary_data nvm = { NULL, 0 };
    if (nvm_arg) {
        nvm = read_file_as_binary_data(nvm_arg);
        if (!nvm.data) {
            free(file.data);
            return 1;
        }
    }

    ia_cmc_t *cmc = ia_cmc_parser_init_v1(&aiqb, nvm.data ? &nvm : NULL);
    if (!cmc) {
        fprintf(stderr, "error: ia_cmc_parser_init_v1() returned NULL -- parser rejected this blob\n");
        free(file.data);
        free(nvm.data);
        return 1;
    }

    if (yaml_mode) {
        cmc_parsed_advanced_color_matrix_t *acm = &cmc->cmc_parsed_advanced_color_matrix;
        if (!acm->cmc_advanced_color_matrix_info || !acm->cmc_parsed_advanced_color_matrices_ls) {
            fprintf(stderr, "error: no advanced color-matrix record in '%s'\n", path_arg);
            ia_cmc_parser_deinit(cmc);
            free(file.data);
            free(nvm.data);
            return 1;
        }
        print_yaml_ccm(acm);
        ia_cmc_parser_deinit(cmc);
        free(file.data);
        free(nvm.data);
        return 0;
    }

    printf("== %s ==\n", path_arg);
    printf("file size %u, inner AIQB blob at offset %ld, size %u%s\n",
           file.size, (long)((unsigned char *)aiqb.data - (unsigned char *)file.data),
           aiqb.size, nvm.data ? " (+ NVM blob)" : "");

    if (cmc->cmc_general_data) {
        cmc_general_data_t *g = cmc->cmc_general_data;
        printf("sensor: %ux%u, %u-bit, color_order=%u\n", g->width, g->height, g->bit_depth, g->color_order);
    }

    /* Modern/advanced per-illuminant CCM -- what Dell/Intel actually ship
     * in these files (the older cmc_parsed_color_matrices record is empty
     * in every file tested). */
    cmc_parsed_advanced_color_matrix_t *acm = &cmc->cmc_parsed_advanced_color_matrix;
    if (acm->cmc_advanced_color_matrix_info && acm->cmc_parsed_advanced_color_matrices_ls) {
        uint16_t n = acm->cmc_advanced_color_matrix_info->light_sources_count;
        uint16_t sectors = acm->cmc_advanced_color_matrix_info->sector_count;
        printf("advanced color matrices: %u light sources, %u hue sectors each\n", n, sectors);
        for (uint16_t i = 0; i < n; i++) {
            cmc_parsed_advanced_color_matrices_ls_t *ls = &acm->cmc_parsed_advanced_color_matrices_ls[i];
            if (!ls->color_matrices_info) continue;
            cmc_acm_color_matrices_info_t *info = ls->color_matrices_info;
            printf("  [%u] light_src=%u (%s) cct=%uK chromaticity=(r/g=%.4f,b/g=%.4f) cie=(x=%.4f,y=%.4f)\n",
                   i, info->src_type, light_source_name((cmc_light_source)info->src_type), info->cct,
                   info->chromaticity[0], info->chromaticity[1], info->src_cie_xy[0], info->src_cie_xy[1]);
            printf("      traditional_color_matrix (all-sector average):\n");
            print_float_matrix(ls->traditional_color_matrix.color_matrix);
        }
    } else {
        printf("no advanced color-matrix record in this file\n");
    }

    /* Legacy record, kept as a fallback in case some file uses it instead. */
    cmc_parsed_color_matrices_t *pcm = &cmc->cmc_parsed_color_matrices;
    if (pcm->cmc_color_matrices && pcm->cmc_color_matrix) {
        printf("legacy color matrices: %u\n", pcm->cmc_color_matrices->num_matrices);
    }

    printf("lens shading present: legacy=%s new=%s\n",
           cmc->cmc_parsed_lens_shading.cmc_lens_shading ? "yes" : "no",
           cmc->cmc_lens_shading ? "yes" : "no");
    printf("lateral chromatic aberration data present: %s\n", cmc->cmc_parsed_lca ? "yes" : "no");

    ia_cmc_parser_deinit(cmc);
    free(file.data);
    free(nvm.data);
    return 0;
}
