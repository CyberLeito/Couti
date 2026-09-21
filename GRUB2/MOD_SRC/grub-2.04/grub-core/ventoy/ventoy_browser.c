/******************************************************************************
 * ventoy_browser.c 
 *
 * Copyright (c) 2022, longpanda <admin@ventoy.net>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 3 of the
 * License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses/>.
 *
 */
#include <grub/types.h>
#include <grub/misc.h>
#include <grub/mm.h>
#include <grub/err.h>
#include <grub/dl.h>
#include <grub/disk.h>
#include <grub/device.h>
#include <grub/term.h>
#include <grub/partition.h>
#include <grub/file.h>
#include <grub/normal.h>
#include <grub/extcmd.h>
#include <grub/datetime.h>
#include <grub/i18n.h>
#include <grub/net.h>
#include <grub/time.h>
#include <grub/ventoy.h>
#include "ventoy_def.h"

GRUB_MOD_LICENSE ("GPLv3+");

#define BROWSER_MENU_BUF    65536

static const char *g_vtoy_dev = NULL;
static grub_disk_addr_t g_browser_boot_start;
static int g_browser_boot_known;
static grub_fs_t g_menu_fs = NULL;
static char *g_menu_device = NULL;
static grub_device_t g_menu_dev = NULL;
static char g_menu_path_buf[1024];
static int g_menu_path_len = 0;
static browser_node *g_browser_list = NULL;

/* Resolve the actual boot partition; its partition number is not fixed. */
static void ventoy_browser_boot_device(void)
{
    const char *locations[2];
    char *name;
    grub_device_t dev;
    int i;

    g_vtoy_dev = grub_env_get("vtoydev");
    g_browser_boot_known = 0;
    locations[0] = grub_env_get("prefix");
    locations[1] = grub_env_get("vtoy_efi_part");
    for (i = 0; i < 2 && !g_browser_boot_known; i++)
    {
        if (!locations[i] || !g_vtoy_dev)
            continue;
        name = grub_file_get_device_name(locations[i]);
        if (!name)
            continue;
        dev = grub_device_open(name);
        grub_free(name);
        if (dev)
        {
            if (dev->disk && dev->disk->partition &&
                grub_strcmp(dev->disk->name, g_vtoy_dev) == 0)
            {
                g_browser_boot_start = grub_partition_get_start(dev->disk->partition);
                g_browser_boot_known = 1;
            }
            grub_device_close(dev);
        }
        grub_errno = GRUB_ERR_NONE;
    }
}

static int ventoy_browser_is_boot(struct grub_disk *disk, const grub_partition_t partition)
{
    return g_browser_boot_known && g_vtoy_dev &&
        grub_strcmp(disk->name, g_vtoy_dev) == 0 &&
        grub_partition_get_start(partition) == g_browser_boot_start;
}

static int ventoy_browser_partition_name(struct grub_disk *disk,
    const grub_partition_t partition, char *buffer, grub_size_t size)
{
    char *name = grub_partition_get_name(partition);
    int len;
    if (!name)
        return 0;
    len = grub_snprintf(buffer, size, "%s,%s", disk->name, name);
    grub_free(name);
    return len > 0 && (grub_size_t)len < size;
}

static int ventoy_browser_strcmp(char *str1, char *str2)
{
    char *s1, *s2;
    int c1 = 0;
    int c2 = 0;

    for (s1 = str1, s2 = str2; *s1 && *s2; s1++, s2++)
    {
        c1 = *s1;
        c2 = *s2;

        if (0 == g_sort_case_sensitive)
        {
            if (grub_islower(c1))
            {
                c1 = c1 - 'a' + 'A';
            }
            
            if (grub_islower(c2))
            {
                c2 = c2 - 'a' + 'A';
            }
        }

        if (c1 != c2)
        {
            break;
        }
    }

    return (c1 - c2);
}

static int ventoy_browser_mbuf_alloc(browser_mbuf *mbuf)
{
    grub_memset(mbuf, 0, sizeof(browser_mbuf));
    mbuf->buf = grub_malloc(BROWSER_MENU_BUF);
    if (!mbuf->buf)
    {
        return 0;
    }

    mbuf->pos = 0;
    mbuf->max = BROWSER_MENU_BUF;
    return 1;
}

static inline void ventoy_browser_mbuf_free(browser_mbuf *mbuf)
{
    if (mbuf)
        grub_check_free(mbuf->buf)
}

static inline int ventoy_browser_mbuf_extend(browser_mbuf *mbuf)
{
    if (mbuf->max - mbuf->pos <= VTOY_SIZE_1KB)
    {
        mbuf->max += BROWSER_MENU_BUF;
        mbuf->buf = grub_realloc(mbuf->buf, mbuf->max);
    }

    return 0;
}

static browser_node * ventoy_browser_find_top_node(int dir)
{
    browser_node *node = NULL;
    browser_node *sel = NULL;

    for (node = g_browser_list; node; node = node->next)
    {
        if (node->dir == dir)
        {
            if (sel)
            {
                if (ventoy_browser_strcmp(sel->filename, node->filename) > 0)
                {
                    sel = node;
                }
            }
            else
            {
                sel = node;
            }
        }
    }
    
    return sel;
}

static int ventoy_browser_iterate_partition(struct grub_disk *disk, const grub_partition_t partition, void *data)
{
    char partname[64];
    char title[256];
    grub_device_t dev;
    grub_fs_t fs;
    char *Label = NULL;
    browser_mbuf *mbuf = (browser_mbuf *)data;

    (void)data;

    if (ventoy_browser_is_boot(disk, partition))
    {
        return 0;
    }

    if (!ventoy_browser_partition_name(disk, partition, partname, sizeof(partname)))
        return 0;

    dev = grub_device_open(partname);
    if (!dev)
    {
        grub_errno = GRUB_ERR_NONE;
        return 0;
    }

    fs = grub_fs_probe(dev);
    if (!fs)
    {
        grub_device_close(dev);
        grub_errno = GRUB_ERR_NONE;
        return 0;
    }

    if (fs->fs_label)
        fs->fs_label(dev, &Label);
    grub_errno = GRUB_ERR_NONE;

    if (ventoy_check_file_exist("(%s)/.ventoyignore", partname))
    {
        grub_free(Label);
        grub_device_close(dev);
        return 0;
    }

    if (g_tree_view_menu_style == 0)
    {
        grub_snprintf(title, sizeof(title), "%-10s (%s) [%s] %s %s", 
            "DISK", partname, (Label ? Label : ""), fs->name, 
            grub_get_human_size(partition->len << disk->log_sector_size, GRUB_HUMAN_SIZE_SHORT));
    }
    else
    {
        grub_snprintf(title, sizeof(title), "(%s) [%s] %s %s", 
            partname, (Label ? Label : ""), fs->name, 
            grub_get_human_size(partition->len << disk->log_sector_size, GRUB_HUMAN_SIZE_SHORT));
    }

    if (ventoy_get_fs_type(fs->name) >= ventoy_fs_max)
    {
        browser_ssprintf(mbuf, "menuentry \"%s\" --class=coutidisk {\n"
            "   echo \"unsupported file system type!\" \n"
            "   ventoy_pause\n"
            "}\n",
            title);
    }
    else
    {
        browser_ssprintf(mbuf, "menuentry \"%s\" --class=coutidisk {\n"
            "  vt_browser_dir %s 0x%lx /\n"
            "}\n",
            title, partname, (ulong)fs);
    }

    ventoy_browser_mbuf_extend(mbuf);

    grub_free(Label);
    grub_device_close(dev);

    return 0;
}

static int ventoy_browser_iterate_disk(const char *name, void *data)
{
    grub_disk_t disk;

    if (name[0] != 'h')
    {
        return 0;
    }

    disk = grub_disk_open(name);
    if (disk)
    {
        grub_partition_iterate(disk, ventoy_browser_iterate_partition, data);
        grub_disk_close(disk);
    }

    return 0;
}

static int ventoy_browser_valid_dirname(const char *name, int len)
{
    if ((len == 1 && name[0] == '.') ||
        (len == 2 && name[0] == '.' && name[1] == '.'))
    {
        return 0;
    }

    if (!ventoy_img_name_valid(name, len))
    {
        return 0;
    }

    if (g_filt_trash_dir)
    {
        if (0 == grub_strncmp(name, ".trash-", 7) ||
            0 == grub_strcmp(name, ".Trashes"))
        {
            return 0;
        }
    }

    if (name[0] == '$')
    {
        if (0 == grub_strncmp(name, "$RECYCLE.BIN", 12) ||
            0 == grub_strncasecmp(name, "$Extend", 7))
        {
            return 0;
        }
    }

    if (len == 25 && grub_strncmp(name, "System Volume Information", 25) == 0)
    {
        return 0;
    }

    return 1;
}

static int ventoy_browser_valid_filename(const char *filename, int len, int *type)
{
    if (len < 4)
    {
        return 0;
    }

    if (FILE_FLT(ISO) && 0 == grub_strcasecmp(filename + len - 4, ".iso"))
    {
        *type = img_type_iso;
    }
    else if (FILE_FLT(WIM) && g_wimboot_enable && (0 == grub_strcasecmp(filename + len - 4, ".wim")))
    {
        *type = img_type_wim;
    }
    else if (FILE_FLT(VHD) && g_vhdboot_enable && (0 == grub_strcasecmp(filename + len - 4, ".vhd") || 
            (len >= 5 && 0 == grub_strcasecmp(filename + len - 5, ".vhdx"))))
    {
        *type = img_type_vhd;
    }
    #ifdef GRUB_MACHINE_EFI
    else if (FILE_FLT(EFI) && 0 == grub_strcasecmp(filename + len - 4, ".efi"))
    {
        *type = img_type_efi;
    }
    #endif
    else if (FILE_FLT(IMG) && 0 == grub_strcasecmp(filename + len - 4, ".img"))
    {
        if (len == 18 && grub_strncmp(filename, "ventoy_", 7) == 0)
        {
            if (grub_strncmp(filename + 7, "wimboot", 7) == 0 ||
                grub_strncmp(filename + 7, "vhdboot", 7) == 0)
            {
                return 0;
            }
        }
        *type = img_type_img;
    }
    else if (FILE_FLT(VTOY) && len >= 5 && 0 == grub_strcasecmp(filename + len - 5, ".vtoy"))
    {
        *type = img_type_vtoy;
    }
    else
    {
        return 0;
    }

    if (g_filt_dot_underscore_file && filename[0] == '.' && filename[1] == '_')
    {
        return 0;
    }

    return 1;
}

static int ventoy_browser_check_ignore(const char *device, const char *root, const char *dir)
{
    grub_file_t file;
    char fullpath[1024] = {0};

    grub_snprintf(fullpath, 1023, "(%s)%s/%s/.ventoyignore", device, root, dir);
    file = grub_file_open(fullpath, GRUB_FILE_TYPE_NONE);
    if (!file)
    {
        grub_errno = 0;
        return 0;
    }
    else
    {
        grub_file_close(file);
        return 1;
    }
}

static int ventoy_browser_iterate_dir(const char *filename, const struct grub_dirhook_info *info, void *data)
{
    int type;
    int len;
    browser_node *node;

    (void)data;

    len = grub_strlen(filename);
    
    if (info->dir)
    {
        if (!ventoy_browser_valid_dirname(filename, len))
        {
            return 0;
        }

        if (ventoy_browser_check_ignore(g_menu_device, g_menu_path_buf, filename))
        {
            return 0;
        }

        node = grub_zalloc(sizeof(browser_node));
        if (!node)
        {
            return 0;
        }

        node->dir = 1;
        grub_strncpy(node->filename, filename, sizeof(node->filename));

        if (g_tree_view_menu_style == 0)
        {
            grub_snprintf(node->menuentry, sizeof(node->menuentry),
                "menuentry \"%-10s [%s]\" --class=coutidir {\n"
                "  vt_browser_dir %s 0x%lx \"%s/%s\"\n"
                "}\n",
                "DIR", filename, g_menu_device, (ulong)g_menu_fs, g_menu_path_buf, filename);
        }
        else
        {
            grub_snprintf(node->menuentry, sizeof(node->menuentry),
                "menuentry \"[%s]\" --class=coutidir {\n"
                "  vt_browser_dir %s 0x%lx \"%s/%s\"\n"
                "}\n",
                filename, g_menu_device, (ulong)g_menu_fs, g_menu_path_buf, filename);
        }
    }
    else
    {
        grub_uint64_t fsize = info->size;
        
        if (!ventoy_browser_valid_filename(filename, len, &type))
        {
            return 0;
        }

        if (grub_file_is_vlnk_suffix(filename, len))
        {
            return 0;
        }

        node = grub_zalloc(sizeof(browser_node));
        if (!node)
        {
            return 0;
        }

        if (fsize == 0)
        {
            struct grub_file file;

            grub_memset(&file, 0, sizeof(file));
            file.device = g_menu_dev;
            grub_snprintf(node->menuentry, sizeof(node->menuentry), "%s/%s", g_menu_path_buf, filename);
            if (g_menu_fs->fs_open(&file, node->menuentry) == GRUB_ERR_NONE)
            {
                fsize = file.size;
                g_menu_fs->fs_close(&file);
            }
        }
        
        node->dir = 0;
        grub_strncpy(node->filename, filename, sizeof(node->filename));

        if (g_tree_view_menu_style == 0)
        {
            grub_snprintf(node->menuentry, sizeof(node->menuentry),
                "menuentry \"%-10s %s\" --class=%s {\n"
                "  vt_set_fake_vlnk \"(%s)%s/%s\" %s %llu\n"
                "  %s_common_menuentry\n"
                "  vt_reset_fake_vlnk\n"
                "}\n",
                grub_get_human_size(fsize, GRUB_HUMAN_SIZE_SHORT), filename, g_menu_class[type],
                g_menu_device, g_menu_path_buf, filename, g_menu_prefix[type], (ulonglong)fsize,
                g_menu_prefix[type]);
        }
        else
        {
            grub_snprintf(node->menuentry, sizeof(node->menuentry),
                "menuentry \"%s\" --class=%s {\n"
                "  vt_set_fake_vlnk \"(%s)%s/%s\" %s %llu\n"
                "  %s_common_menuentry\n"
                "  vt_reset_fake_vlnk\n"
                "}\n",
                filename, g_menu_class[type],
                g_menu_device, g_menu_path_buf, filename, g_menu_prefix[type], (ulonglong)fsize,
                g_menu_prefix[type]);
        }
    }

    node->prev = NULL;
    node->next = g_browser_list;
    if (g_browser_list)
    {
        g_browser_list->prev = node;
    }
    g_browser_list = node;

    return 0;
}

grub_err_t ventoy_cmd_browser_dir(grub_extcmd_context_t ctxt, int argc, char **args)
{
    int i;
    grub_fs_t fs;
    grub_device_t dev;
    char cfgfile[64];
    browser_node *node;
    browser_mbuf mbuf;
    int main_menu;
    grub_err_t err;

    (void)ctxt;
    if (argc < 3 || args[2][0] != '/')
        return grub_error(GRUB_ERR_BAD_ARGUMENT, "Expected a device and absolute directory path");
    main_menu = argc > 3 && grub_strcmp(args[3], "--main") == 0;
    
    dev = grub_device_open(args[0]);
    if (!dev)
    {
        debug("Failed to open device %s\n", args[0]);
        return 1;
    }

    /* Probe the selected device instead of relying on a saved FS pointer. */
    fs = grub_fs_probe(dev);
    if (!fs || !fs->fs_dir || !ventoy_browser_mbuf_alloc(&mbuf))
    {
        grub_device_close(dev);
        return 1;
    }
    
    g_menu_fs = fs;
    g_menu_device = args[0];
    g_menu_dev = dev;
    g_browser_list = NULL;

    if (args[2][0] == '/' && args[2][1] == 0)
    {
        g_menu_path_len = 0;
        g_menu_path_buf[0] = 0;
        err = fs->fs_dir(dev, "/", ventoy_browser_iterate_dir, NULL);
    }
    else
    {
        g_menu_path_len = grub_snprintf(g_menu_path_buf, sizeof(g_menu_path_buf), "%s", args[2]);
        err = fs->fs_dir(dev, g_menu_path_buf, ventoy_browser_iterate_dir, NULL);
    }
    grub_device_close(dev);
    if (err)
    {
        while (g_browser_list)
        {
            node = g_browser_list;
            g_browser_list = node->next;
            grub_free(node);
        }
        ventoy_browser_mbuf_free(&mbuf);
        return err;
    }

    if (main_menu)
    {
        browser_ssprintf(&mbuf,
            "menuentry \"[ .. ] Choose a different partition (current: %s)\" --class=coutiret {\n"
            "  vt_browser_disk\n}\n", args[0]);
    }
    else if (g_tree_view_menu_style == 0)
    {
        browser_ssprintf(&mbuf, "menuentry \"%-10s [(%s)%s/..]\" --class=\"coutiret\" VTOY_RET {\n  "
                         "  echo 'return ...' \n}\n", "<--", args[0], g_menu_path_buf);        
    }
    else
    {
        browser_ssprintf(&mbuf, "menuentry \"[(%s)%s/..]\" --class=\"coutiret\" VTOY_RET {\n  "
                         "  echo 'return ...' \n}\n", args[0], g_menu_path_buf);        
    }

    for (i = 1; i >= 0; i--)
    {
        while (1)
        {
            node = ventoy_browser_find_top_node(i);
            if (node)
            {
                browser_ssprintf(&mbuf, "%s", node->menuentry);
                ventoy_browser_mbuf_extend(&mbuf);
                
                if (node->prev)
                {
                    node->prev->next = node->next;
                }
                if (node->next)
                {
                    node->next->prev = node->prev;
                }

                if (node == g_browser_list)
                {
                    g_browser_list = node->next;
                }
                grub_free(node);
            }
            else
            {
                break;
            }
        }
    }
    g_browser_list = NULL;
    
    if (main_menu)
        grub_script_execute_sourcecode(mbuf.buf);
    else
    {
        grub_snprintf(cfgfile, sizeof(cfgfile), "configfile mem:0x%lx:size:%d", (ulong)mbuf.buf, mbuf.pos);
        grub_script_execute_sourcecode(cfgfile);
    }

    ventoy_browser_mbuf_free(&mbuf);
    VENTOY_CMD_RETURN(GRUB_ERR_NONE);
}

grub_err_t ventoy_cmd_browser_disk(grub_extcmd_context_t ctxt, int argc, char **args)
{
    char cfgfile[64];
    browser_mbuf mbuf;
    int main_menu = argc > 0 && grub_strcmp(args[0], "--main") == 0;
    
    (void)ctxt;
    (void)argc;
    (void)args;

    if (!ventoy_browser_mbuf_alloc(&mbuf))
    {
        return 1;
    }

    ventoy_browser_boot_device();

    if (main_menu)
    {
        /* No parent menu exists when no default data partition is readable. */
    }
    else if (g_tree_view_menu_style == 0)
    {
        browser_ssprintf(&mbuf, "menuentry \"%-10s [%s]\" --class=\"coutiret\" VTOY_RET {\n  "
                         "  echo 'return ...' \n}\n", "<--", 
                         ventoy_get_vmenu_title("VTLANG_BROWER_RETURN"));        
    }
    else
    {
        browser_ssprintf(&mbuf, "menuentry \"[%s]\" --class=\"coutiret\" VTOY_RET {\n  "
                         "  echo 'return ...' \n}\n", 
                         ventoy_get_vmenu_title("VTLANG_BROWER_RETURN"));      
    }

    grub_disk_dev_iterate(ventoy_browser_iterate_disk, &mbuf);

    if (mbuf.pos == 0)
        browser_ssprintf(&mbuf, "menuentry \"No readable partitions found\" --class=coutidisk { true }\n");

    if (main_menu)
        grub_script_execute_sourcecode(mbuf.buf);
    else
    {
        grub_snprintf(cfgfile, sizeof(cfgfile), "configfile mem:0x%lx:size:%d", (ulong)mbuf.buf, mbuf.pos);
        grub_script_execute_sourcecode(cfgfile);
    }

    ventoy_browser_mbuf_free(&mbuf);
    VENTOY_CMD_RETURN(GRUB_ERR_NONE);
}

typedef struct browser_home
{
    char device[64];
    grub_disk_addr_t size;
} browser_home;

static int couti_find_boot_partition(struct grub_disk *disk,
    const grub_partition_t partition, void *data)
{
    char *device = data;
    char name[64];
    if (ventoy_browser_partition_name(disk, partition, name, sizeof(name)) &&
        ventoy_check_file_exist("(%s)/couti/couti.cpio", name) &&
        ventoy_check_file_exist("(%s)/grub/grub.cfg", name))
    {
        grub_strcpy(device, name);
        return 1;
    }
    grub_errno = GRUB_ERR_NONE;
    return 0;
}

/* This runs from the embedded config: never choose a different physical disk. */
grub_err_t ventoy_cmd_couti_find_boot(grub_extcmd_context_t ctxt, int argc, char **args)
{
    const char *locations[3];
    char device[64] = {0};
    char path[96];
    char *name;
    grub_device_t dev;
    grub_disk_t disk;
    int i;
    (void)ctxt; (void)argc; (void)args;
    locations[0] = grub_env_get("cmdpath");
    locations[1] = grub_env_get("root");
    locations[2] = grub_env_get("prefix");
    for (i = 0; i < 3 && !device[0]; i++)
    {
        if (!locations[i]) continue;
        name = locations[i][0] == '(' ? grub_file_get_device_name(locations[i]) : grub_strdup(locations[i]);
        if (!name) continue;
        dev = grub_device_open(name);
        if (dev && dev->disk)
        {
            if (dev->disk->partition && ventoy_check_file_exist("(%s)/couti/couti.cpio", name))
                grub_strncpy(device, name, sizeof(device) - 1);
            else
            {
                disk = grub_disk_open(dev->disk->name);
                if (disk)
                {
                    grub_partition_iterate(disk, couti_find_boot_partition, device);
                    grub_disk_close(disk);
                }
            }
        }
        if (dev) grub_device_close(dev);
        grub_free(name);
        grub_errno = GRUB_ERR_NONE;
    }
    if (!device[0])
        return grub_error(GRUB_ERR_FILE_NOT_FOUND, "Couti boot partition not found on the boot disk");
    grub_env_set("root", device);
    grub_snprintf(path, sizeof(path), "(%s)/grub", device);
    grub_env_set("prefix", path);
    return GRUB_ERR_NONE;
}

static int ventoy_browser_find_home(struct grub_disk *disk,
    const grub_partition_t partition, void *data)
{
    browser_home *home = data;
    char name[64];
    grub_device_t dev;
    grub_fs_t fs;

    if (ventoy_browser_is_boot(disk, partition) || partition->len <= home->size ||
        !ventoy_browser_partition_name(disk, partition, name, sizeof(name)))
        return 0;
    dev = grub_device_open(name);
    if (dev)
    {
        fs = grub_fs_probe(dev);
        if (fs && fs->fs_dir && ventoy_get_fs_type(fs->name) < ventoy_fs_max &&
            !ventoy_check_file_exist("(%s)/.ventoyignore", name))
        {
            grub_strcpy(home->device, name);
            home->size = partition->len;
        }
        grub_device_close(dev);
    }
    grub_errno = GRUB_ERR_NONE;
    return 0;
}

/* Set helper/plugin paths before collecting images or entering the menu. */
grub_err_t ventoy_cmd_couti_layout(grub_extcmd_context_t ctxt, int argc, char **args)
{
    browser_home home;
    char path[96], number[16];
    char *name;
    grub_device_t dev;
    grub_disk_t disk;
    const char *prefix = grub_env_get("prefix");
    (void)ctxt; (void)argc; (void)args;
    if (!prefix) return grub_error(GRUB_ERR_BAD_DEVICE, "Missing Couti boot location");
    name = grub_file_get_device_name(prefix);
    if (!name) return grub_error(GRUB_ERR_BAD_DEVICE, "Invalid Couti boot location");
    dev = grub_device_open(name);
    if (!dev || !dev->disk || !dev->disk->partition)
    {
        if (dev) grub_device_close(dev);
        grub_free(name);
        return grub_error(GRUB_ERR_BAD_DEVICE, "Couti must boot from a disk partition");
    }
    grub_env_set("vtoydev", dev->disk->name);
    grub_snprintf(number, sizeof(number), "%u", dev->disk->partition->number + 1);
    grub_env_set("couti_boot_partition", number);
    grub_snprintf(path, sizeof(path), "(%s)", name);
    grub_env_set("vtoy_efi_part", path);
    grub_device_close(dev);
    grub_free(name);
    ventoy_browser_boot_device();
    grub_memset(&home, 0, sizeof(home));
    disk = g_vtoy_dev ? grub_disk_open(g_vtoy_dev) : NULL;
    if (disk)
    {
        grub_partition_iterate(disk, ventoy_browser_find_home, &home);
        grub_disk_close(disk);
    }
    grub_errno = GRUB_ERR_NONE;
    if (home.device[0])
    {
        grub_snprintf(path, sizeof(path), "(%s)", home.device);
        grub_env_set("vtoy_iso_part", path);
    }
    return GRUB_ERR_NONE;
}

grub_err_t ventoy_cmd_browser_home(grub_extcmd_context_t ctxt, int argc, char **args)
{
    browser_home home;
    grub_disk_t disk;
    char fs[] = "0";
    char root[] = "/";
    char mode[] = "--main";
    char *dir_args[] = { home.device, fs, root, mode };
    char *disk_args[] = { mode };

    (void)argc;
    (void)args;
    grub_memset(&home, 0, sizeof(home));
    ventoy_browser_boot_device();
    /* Do not silently select a different disk when the boot drive is absent. */
    disk = g_vtoy_dev && g_browser_boot_known ? grub_disk_open(g_vtoy_dev) : NULL;
    if (disk)
    {
        grub_partition_iterate(disk, ventoy_browser_find_home, &home);
        grub_disk_close(disk);
    }
    grub_errno = GRUB_ERR_NONE;
    if (home.device[0] && ventoy_cmd_browser_dir(ctxt, 4, dir_args) == GRUB_ERR_NONE)
        return GRUB_ERR_NONE;

    grub_errno = GRUB_ERR_NONE;
    return ventoy_cmd_browser_disk(ctxt, 1, disk_args);
}

