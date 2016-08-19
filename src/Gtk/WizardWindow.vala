/*
 * WizardWindow.vala
 *
 * Copyright 2013 Tony George <teejee@tony-pc>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */

using Gtk;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.Devices;
using TeeJee.JsonHelper;
using TeeJee.ProcessHelper;
using TeeJee.GtkHelper;
using TeeJee.System;
using TeeJee.Misc;

class WizardWindow : Gtk.Window{

	private Gtk.Box vbox_main;
	private Notebook notebook;
	private Gtk.TreeView tv_devices;
	private Gtk.RadioButton radio_device;
	private Gtk.RadioButton radio_path;
	private Gtk.Entry entry_backup_path;
	private Gtk.InfoBar infobar_device;
	private Gtk.Label lbl_infobar_device;
	private Gtk.InfoBar infobar_path;
	private Gtk.Label lbl_infobar_path;

	private Gtk.Spinner spinner;
	private Gtk.Label lbl_msg;
	private Gtk.Label lbl_status;
	private ProgressBar progressbar;
	private Gtk.Button btn_cancel_snapshot;
	
	private uint tmr_init;
	
	public WizardWindow () {
		this.title = AppName + " v" + AppVersion;
        this.window_position = WindowPosition.CENTER;
        this.modal = true;
        this.set_default_size (500, 500);
		//this.delete_event.connect(on_delete_event);
		this.icon = get_app_icon(16);

	    // vbox_main
        var box = new Box (Orientation.VERTICAL, 6);
        box.margin = 0; // keep 0 as we will hide tabs in Wizard view
        add(box);
		vbox_main = box;
        
		notebook = add_notebook(box, false, false);
		notebook.margin = 6;
		
		create_tab_backup_device();

		create_tab_first_snapshot();

		create_actions();

		show_all();

		log_msg("here2");

		tmr_init = Timeout.add(100, init_delayed);
    }

    private bool init_delayed(){

		if (tmr_init > 0){
			Source.remove(tmr_init);
			tmr_init = 0;
		}

		tv_devices_refresh();

		if (App.snapshot_path.length > 0){
			entry_backup_path.text = App.snapshot_path;
		}

		if (App.snapshot_device != null){
			select_backup_device(App.snapshot_device);
		}

		if (App.use_snapshot_path){
			radio_path.active = true;
		}
		else{
			radio_device.active = true;
		}

		radio_device.toggled();
		radio_path.toggled();

		
		
		return false;
	}

	private void create_tab_backup_device(){

		var box = add_tab(notebook, _("Backup Device"));
		
		add_label_header(box, _("Select Snapshot Location"), true);

		// section device
		
		radio_device = add_radio(box, "<b>%s</b>".printf(_("Save to disk partition:")), null);

		var msg = _("Only Linux partitions are supported.");
		msg += "\n" + _("Snapshots will be saved in folder /timeshift");
				
		//var lbl_device_subnote = add_label_subnote(box,msg);

		radio_device.toggled.connect(() =>{
			tv_devices.sensitive = radio_device.active;
			//lbl_device_subnote.sensitive = radio_device.active;
			infobar_device.visible = radio_device.active;

			if (radio_device.active){
				if (App.snapshot_device != null){
					select_backup_device(App.snapshot_device);
				}

				App.use_snapshot_path = false;
			}
			
			check_backup_location();
		});
		
		create_device_list(box);

		create_infobar_device(box);

		radio_device.set_tooltip_text(msg);
		tv_devices.set_tooltip_text(msg);

		// section path
		
		radio_path = add_radio(box, "<b>%s</b>".printf(_("Save to specified path:")), radio_device);
		radio_path.margin_top = 12;

		msg = _("File system at selected path must support hard-links");
		//var lbl_path_subnote = add_label_subnote(box,msg);

		entry_backup_path = add_directory_chooser(box, App.snapshot_path);

		radio_path.toggled.connect(()=>{
			entry_backup_path.sensitive = radio_path.active;
			//lbl_path_subnote.sensitive = radio_path.active;
			infobar_path.visible = radio_path.active;
			if (radio_path.active){
				entry_backup_path.text = App.snapshot_path;
			}
			check_backup_location();
		});

		create_infobar_path(box);

		radio_path.set_tooltip_text(msg);
		entry_backup_path.set_tooltip_text(msg);
	}

	private void create_tab_first_snapshot(){

		var box = add_tab(notebook, _("Progress"));
		
		add_label_header(box, _("Creating Snapshot..."), true);

		var hbox_status = new Box (Orientation.HORIZONTAL, 6);
		box.add (hbox_status);
		
		spinner = new Gtk.Spinner();
		spinner.active = true;
		hbox_status.add(spinner);
		
		//lbl_msg
		lbl_msg = add_label(box, "");
		lbl_msg.halign = Align.START;
		lbl_msg.ellipsize = Pango.EllipsizeMode.END;
		lbl_msg.max_width_chars = 40;

		//progressbar
		progressbar = new Gtk.ProgressBar();
		//progressbar.pulse_step = 0.1;
		box.pack_start (progressbar, false, true, 0);

		//lbl_status
		lbl_status = add_label(box, "");
		lbl_status.halign = Align.START;
		lbl_status.ellipsize = Pango.EllipsizeMode.END;
		lbl_status.max_width_chars = 40;
	}

	private void create_actions(){
		var hbox = new Gtk.ButtonBox (Gtk.Orientation.HORIZONTAL);
		hbox.set_layout (Gtk.ButtonBoxStyle.EXPAND);
		hbox.margin = 0;
		hbox.margin_top = 24;
		hbox.margin_left = 24;
		hbox.margin_right = 24;
		hbox.margin_bottom = 12;
        vbox_main.add(hbox);

		Gtk.SizeGroup size_group = null;
		
		// previous
		
		Gtk.Image img = new Image.from_stock("gtk-go-back", Gtk.IconSize.BUTTON);
		var button = add_button(hbox, _("Previous"), "", ref size_group, img);

        button.clicked.connect(()=>{
			go_prev();
		});

		// next
		
		img = new Image.from_stock("gtk-go-forward", Gtk.IconSize.BUTTON);
		button = add_button(hbox, _("Next"), "", ref size_group, img);

        button.clicked.connect(()=>{
			go_next();
		});

		// cancel
		
		img = new Image.from_stock("gtk-close", Gtk.IconSize.BUTTON);
		button = add_button(hbox, _("Close"), "", ref size_group, img);

        button.clicked.connect(()=>{
			this.destroy();
		});

		
	}
	
	private void create_device_list(Gtk.Box box){
		tv_devices = add_treeview(box);

		// device name
		
		//Gtk.CellRendererPixbuf cell_pix;
		Gtk.CellRendererToggle cell_radio;
		Gtk.CellRendererText cell_text;
		var col = add_column_radio_and_text(tv_devices, _("Disk"), out cell_radio, out cell_text);

		/*col.set_cell_data_func(cell_pix, (cell_layout, cell, model, iter)=>{
			Gdk.Pixbuf pix = null;
			model.get (iter, 2, out pix, -1);

			Device dev;
			model.get (iter, 0, out dev, -1);

			(cell as Gtk.CellRendererPixbuf).pixbuf =  pix;
			(cell as Gtk.CellRendererPixbuf).sensitive = (dev.type != "disk");
			
		});*/

		col.set_cell_data_func(cell_radio, (cell_layout, cell, model, iter)=>{
			Device dev;
			bool selected;
			model.get (iter, 0, out dev, 3, out selected, -1);

			(cell as Gtk.CellRendererToggle).active = selected;

			(cell as Gtk.CellRendererToggle).visible =
				(dev.type != "disk") && ((dev.fstype != "luks") || (dev.children.size == 0));
		});

		//cell_radio.toggled.connect((path)=>{});

		col.set_cell_data_func(cell_text, (cell_layout, cell, model, iter)=>{
			Device dev;
			model.get (iter, 0, out dev, -1);

			/*if (dev.type == "disk"){
				var txt = "%s %s".printf(dev.model, dev.vendor).strip();
				if (txt.length == 0){
					txt = "%s Disk".printf(format_file_size(dev.size_bytes));
				}
				else{
					txt += " (%s Disk)".printf(format_file_size(dev.size_bytes));
				}
				(cell as Gtk.CellRendererText).text = txt.strip();
			}
			else {
				(cell as Gtk.CellRendererText).text = dev.description_full_free();
			}*/

			if (dev.type == "disk"){
				var txt = "%s %s".printf(dev.model, dev.vendor).strip();
				if (txt.length == 0){
					txt = "%s Disk".printf(format_file_size(dev.size_bytes));
				}
				(cell as Gtk.CellRendererText).text = txt.strip();
			}
			else {
				(cell as Gtk.CellRendererText).text = dev.kname;
			}

			//(cell as Gtk.CellRendererText).sensitive = (dev.type != "disk");
		});

		
		// type
		
		col = add_column_text(tv_devices, _("Type"), out cell_text);

		col.set_cell_data_func(cell_text, (cell_layout, cell, model, iter)=>{
			Device dev;
			model.get (iter, 0, out dev, -1);
			(cell as Gtk.CellRendererText).text = dev.fstype;

			//(cell as Gtk.CellRendererText).sensitive = (dev.type != "disk");
		});

		// free
		
		col = add_column_text(tv_devices, _("Free"), out cell_text);
		cell_text.xalign = (float) 1.0;
		
		col.set_cell_data_func(cell_text, (cell_layout, cell, model, iter)=>{
			Device dev;
			model.get (iter, 0, out dev, -1);

			if (dev.type == "disk"){
				(cell as Gtk.CellRendererText).text = "";
			}
			else{
				(cell as Gtk.CellRendererText).text =
					(dev.free_bytes > 0) ? format_file_size(dev.free_bytes) : "";
			}

			(cell as Gtk.CellRendererText).sensitive = (dev.type != "disk");
		});
		
		// size
		
		col = add_column_text(tv_devices, _("Size"), out cell_text);
		cell_text.xalign = (float) 1.0;
		
		col.set_cell_data_func(cell_text, (cell_layout, cell, model, iter)=>{
			Device dev;
			model.get (iter, 0, out dev, -1);

			(cell as Gtk.CellRendererText).text =
					(dev.size_bytes > 0) ? format_file_size(dev.size_bytes) : "";
		});

		
		// buffer

		col = add_column_text(tv_devices, "", out cell_text);
		col.expand = true;
		
		/*// label
		
		col = add_column_text(tv_devices, _("Label"), out cell_text);

		col.set_cell_data_func(cell_text, (cell_layout, cell, model, iter)=>{
			Device dev;
			model.get (iter, 0, out dev, -1);
			(cell as Gtk.CellRendererText).text = dev.label;

			(cell as Gtk.CellRendererText).sensitive = (dev.type != "disk");
		});*/

		
		
		// events

		tv_devices.cursor_changed.connect(() => {
			var store = (Gtk.TreeStore) tv_devices.model;
			var selection = tv_devices.get_selection();

			selection.selected_foreach((model, path, iter) => {
				Device dev;
				store.get (iter, 0, out dev);

				if ((App.snapshot_device == null) || (App.snapshot_device.uuid != dev.uuid)){
					try_change_device(dev);
				}
				else{
					return;
				}
			});

			store.foreach((model, path, iter) => {
				Device dev;
				store.get (iter, 0, out dev);
				
				if ((App.snapshot_device != null) && (App.snapshot_device.uuid == dev.uuid)){
					store.set (iter, 3, true);
					//tv_devices.get_selection().select_iter(iter);
				}
				else{
					store.set (iter, 3, false);
				}

				return false; // continue
			});
		});
	}

	private void try_change_device(Device dev){

		if (dev.type == "disk"){
			bool found_child = false;
			foreach (var child in dev.children){
				if (child.has_linux_filesystem()){
					change_backup_device(child);
					found_child = true;
					break;
				}
			}
			if (!found_child){
				lbl_infobar_device.label = "<span weight=\"bold\">%s</span>".printf(
				_("Selected disk does not have Linux partitions"));
				infobar_device.message_type = Gtk.MessageType.ERROR;
				infobar_device.no_show_all = false;
				infobar_device.show_all();
			}
		}
		else if (!dev.has_children()){
			change_backup_device(dev);
		}
		else if (dev.has_children()){
			change_backup_device(dev.children[0]);
		}
		else {
			lbl_infobar_device.label = "<span weight=\"bold\">%s</span>".printf(
				_("Select a partition on this disk"));
			infobar_device.message_type = Gtk.MessageType.ERROR;
			infobar_device.no_show_all = false;
			infobar_device.show_all();
		}
	}

	private void create_infobar_device(Gtk.Box box){
		var infobar = new Gtk.InfoBar();
		infobar.no_show_all = true;
		box.add(infobar);
		infobar_device = infobar;
		
		var content = (Gtk.Box) infobar.get_content_area ();
		var label = add_label(content, "");
		lbl_infobar_device = label;
	}

	private void create_infobar_path(Gtk.Box box){
		var infobar = new Gtk.InfoBar();
		infobar.no_show_all = true;
		box.add(infobar);
		infobar_path = infobar;
		
		var content = (Gtk.Box) infobar.get_content_area ();
		var label = add_label(content, "");
		lbl_infobar_path = label;
	}
	
	private void change_backup_device(Device pi){
		// return if device has not changed
		if ((App.snapshot_device != null) && (pi.uuid == App.snapshot_device.uuid)){ return; }

		gtk_set_busy(true, this);
		
		//Device previous_device = App.snapshot_device;
		App.snapshot_device = pi;

		log_debug("selected: %s".printf(pi.device));
		
		// try mounting the device
		if (App.mount_backup_device(this)){
			App.update_partitions();

			var newpi = Device.find_device_in_list(App.partitions,pi.device,pi.uuid);

			log_debug("newpi: %s".printf(pi.device));
			log_debug("pi.fstype: %s".printf(pi.fstype));
			log_debug("pi.child_device: %s".printf(
				(pi.children.size == 0) ? "null" : pi.children[0].device));
			
			if ((pi.fstype == "luks") && !pi.has_children() && newpi.has_children()){
				App.snapshot_device = newpi.children[0];
				tv_devices_refresh();
			}
		}

		//if (App.snapshot_device != null){
		//	log_msg("Snapshot device: %s".printf(App.snapshot_device.description()));
		//}

		check_backup_location();

		gtk_set_busy(false, this);
	}

	private void select_backup_device(Device pi){

		tv_devices.get_selection().unselect_all();

		if (App.snapshot_device == null){
			return;
		}
		
		Gtk.TreeIter iter;
		var store = (Gtk.TreeStore) tv_devices.model;

		bool iterExists = store.get_iter_first (out iter);
		while (iterExists) {
			Device dev;
			store.get (iter, 0, out dev);

			if (dev.uuid == App.snapshot_device.uuid){
				tv_devices.get_selection().select_iter(iter);
				break;
			}
			else{
				iterExists = store.iter_next (ref iter);
			}
		}
	}

	private bool check_backup_location(){
		bool ok = true;
		string message, details;
		int status_code = App.check_backup_location(out message, out details);
		
		switch (status_code){
			case SnapshotLocationStatus.NOT_AVAILABLE:
			case SnapshotLocationStatus.HAS_SNAPSHOTS_NO_SPACE:
			case SnapshotLocationStatus.NO_SNAPSHOTS_NO_SPACE:
				lbl_infobar_device.label = "<span weight=\"bold\">%s</span>".printf(message);
				infobar_device.message_type = Gtk.MessageType.ERROR;
				infobar_device.no_show_all = false;
				infobar_device.show_all();
				ok = false;
				break;

			case SnapshotLocationStatus.READ_ONLY_FS:
			case SnapshotLocationStatus.HARDLINKS_NOT_SUPPORTED:
				lbl_infobar_path.label = "<span weight=\"bold\">%s</span>".printf(message);
				infobar_path.message_type = Gtk.MessageType.ERROR;
				infobar_path.no_show_all = false;
				infobar_path.show_all();
				ok = false;
				break;

			case 3:
			case 0:
				infobar_device.hide();
				infobar_path.hide();
				break;
		}

		return ok;
	}

	/*private bool check_backup_path(string path){
		bool ok = true;
		bool is_readonly;
		bool hardlink_supported = filesystem_supports_hardlinks(path, out is_readonly);
		
		if (is_readonly){
			var msg = _("File system at selected path is read-only!") + "\n";
			msg += _("Please select another path.");
			lbl_infobar_path.label = "<span weight=\"bold\">%s</span>".printf(msg);
			infobar_path.message_type = Gtk.MessageType.ERROR;
			infobar_path.no_show_all = false;
			infobar_path.show_all();
			ok = false;
		}
		else if (!hardlink_supported){
			var msg = _("File system at selected path does not support hard-links!") + "\n";
			msg += _("Please select another path.");
			lbl_infobar_path.label = "<span weight=\"bold\">%s</span>".printf(msg);
			infobar_path.message_type = Gtk.MessageType.ERROR;
			infobar_path.no_show_all = false;
			infobar_path.show_all();
			ok = false;
		}
		else{
			infobar_path.hide();
		}

		return ok;
	}*/

	private void tv_devices_refresh(){
		App.update_partitions();

		var model = new Gtk.TreeStore(4,
			typeof(Device),
			typeof(string),
			typeof(Gdk.Pixbuf),
			typeof(bool));
		
		tv_devices.set_model (model);

		Gdk.Pixbuf pix_device = get_shared_icon("disk","disk.png",16).pixbuf;

		TreeIter iter0, iter_selected, iter_dummy;

		model.append(out iter_dummy, null);
		iter_selected = iter_dummy;
		model.clear();

		foreach(var disk in App.partitions) {
			if (disk.type != "disk") { continue; }

			model.append(out iter0, null);
			model.set(iter0, 0, disk, -1);
			model.set(iter0, 1, disk.tooltip_text(), -1);
			model.set(iter0, 2, pix_device, -1);
			model.set(iter0, 3, false, -1);

			tv_append_child_volumes(ref model, ref iter0, disk, ref iter_selected);
		}

		//TODO: pre-select the current App.snapshot_device

		//if (iter_selected != iter_dummy){
			//tv_devices.get_selection().select_iter(iter_selected);
		//}

		tv_devices.expand_all();
	}

	private void tv_append_child_volumes(
		ref Gtk.TreeStore model, ref Gtk.TreeIter iter0,
		Device parent, ref Gtk.TreeIter iter_selected){
			
		Gdk.Pixbuf pix_device = get_shared_icon("disk","disk.png",16).pixbuf;
		Gdk.Pixbuf pix_locked = get_shared_icon("locked","locked.png",16).pixbuf;
		Gdk.Pixbuf pix_unlocked = get_shared_icon("unlocked","unlocked.png",16).pixbuf;
		
		foreach(var part in App.partitions) {

			if (!part.has_linux_filesystem()){ continue; }
			
			if (part.pkname == parent.kname) {
				TreeIter iter1;
				model.append(out iter1, iter0);
				model.set(iter1, 0, part, -1);
				model.set(iter1, 1, part.tooltip_text(), -1);
				model.set(iter1, 2, (part.fstype == "luks") ? pix_locked : pix_device, -1);
				
				
				if (parent.fstype == "luks"){
					// change parent's icon to unlocked
					model.set(iter0, 2, pix_unlocked, -1);
				}

				if ((App.snapshot_device != null) && (part.uuid == App.snapshot_device.uuid)){
					//iter_selected = iter1;
					model.set(iter1, 3, true, -1);
				}
				else{
					model.set(iter1, 3, false, -1);
				}

				tv_append_child_volumes(ref model, ref iter1, part, ref iter_selected);
			}
		}
	}

	private void take_first_snapshot(){
		App.take_snapshot(true,"",this);
	}

	private void go_prev(){
		notebook.prev_page();
	}
	
	private void go_next(){
		if (notebook.page == 0){
			if (check_backup_location()){
				notebook.next_page();
			}
			else{
				gtk_messagebox(
					"Snapshot location not selected",
					"Please select a valid device or path",
					this, true);
			}
		}
	}
	
	// utility ------------------
	
	private Gtk.Notebook add_notebook(Gtk.Box box, bool show_tabs = true, bool show_border = true){
        // notebook
		var book = new Gtk.Notebook();
		book.margin = 6;
		book.show_tabs = show_tabs;
		book.show_border = show_border;
		
		box.pack_start(book, true, true, 0);
		
		return book;
	}

	private Gtk.Box add_tab(Gtk.Notebook book, string title, int margin = 6, int spacing = 6){
		// label
		var label = new Gtk.Label(title);

        // vbox
        var vbox = new Box (Gtk.Orientation.VERTICAL, spacing);
        vbox.margin = margin;
        book.append_page (vbox, label);

        return vbox;
	}

	private Gtk.TreeView add_treeview(Gtk.Box box,
		Gtk.SelectionMode selection_mode = Gtk.SelectionMode.SINGLE){
			
		// TreeView
		var treeview = new TreeView();
		treeview.get_selection().mode = selection_mode;
		treeview.set_rules_hint (true);
		treeview.show_expanders = true;
		treeview.enable_tree_lines = true;

		// ScrolledWindow
		var scrollwin = new ScrolledWindow(null, null);
		scrollwin.set_shadow_type (ShadowType.ETCHED_IN);
		scrollwin.add (treeview);
		scrollwin.expand = true;
		box.add(scrollwin);

		return treeview;
	}

	private Gtk.TreeViewColumn add_column_text(
		Gtk.TreeView treeview, string title, out Gtk.CellRendererText cell){
			
		// TreeViewColumn
		var col = new Gtk.TreeViewColumn();
		col.title = title;
		
		cell = new Gtk.CellRendererText();
		cell.xalign = (float) 0.0;
		col.pack_start (cell, false);
		treeview.append_column(col);
		
		return col;
	}

	private Gtk.TreeViewColumn add_column_icon(
		Gtk.TreeView treeview, string title, out Gtk.CellRendererPixbuf cell){
		
		// TreeViewColumn
		var col = new Gtk.TreeViewColumn();
		col.title = title;
		
		cell = new Gtk.CellRendererPixbuf();
		cell.xpad = 2;
		col.pack_start (cell, false);
		treeview.append_column(col);

		return col;
	}

	private Gtk.TreeViewColumn add_column_icon_and_text(
		Gtk.TreeView treeview, string title,
		out Gtk.CellRendererPixbuf cell_pix, out Gtk.CellRendererText cell_text){
			
		// TreeViewColumn
		var col = new Gtk.TreeViewColumn();
		col.title = title;

		cell_pix = new Gtk.CellRendererPixbuf();
		cell_pix.xpad = 2;
		col.pack_start (cell_pix, false);
		
		cell_text = new Gtk.CellRendererText();
		cell_text.xalign = (float) 0.0;
		col.pack_start (cell_text, false);
		treeview.append_column(col);

		return col;
	}

	private Gtk.TreeViewColumn add_column_radio_and_text(
		Gtk.TreeView treeview, string title,
		out Gtk.CellRendererToggle cell_radio, out Gtk.CellRendererText cell_text){
			
		// TreeViewColumn
		var col = new Gtk.TreeViewColumn();
		col.title = title;

		cell_radio = new Gtk.CellRendererToggle();
		cell_radio.xpad = 2;
		cell_radio.radio = true;
		cell_radio.activatable = true;
		col.pack_start (cell_radio, false);
		
		cell_text = new Gtk.CellRendererText();
		cell_text.xalign = (float) 0.0;
		col.pack_start (cell_text, false);
		treeview.append_column(col);

		return col;
	}

	private Gtk.Label add_label(
		Gtk.Box box, string text, bool is_bold = false, bool is_italic = false, bool is_large = false){
			
		string msg = "<span%s%s%s>%s</span>".printf(
			(is_bold ? " weight=\"bold\"" : ""),
			(is_italic ? " style=\"italic\"" : ""),
			(is_large ? " size=\"x-large\"" : ""),
			text);
			
		var label = new Gtk.Label(msg);
		label.set_use_markup(true);
		label.xalign = (float) 0.0;
		box.add(label);
		return label;
	}

	private Gtk.Label add_label_header(
		Gtk.Box box, string text, bool large_heading = false){
		
		var label = add_label(box, text, true, false, large_heading);
		label.margin_bottom = 12;
		return label;
	}

	private Gtk.Label add_label_subnote(
		Gtk.Box box, string text){
		
		var label = add_label(box, text, false, true);
		label.margin_left = 6;
		return label;
	}

	private Gtk.RadioButton add_radio(Gtk.Box box, string text, Gtk.RadioButton? another_radio_in_group){

		Gtk.RadioButton radio = null;

		if (another_radio_in_group == null){
			radio = new Gtk.RadioButton(null);
		}
		else{
			radio = new Gtk.RadioButton.from_widget(another_radio_in_group);
		}

		radio.label = text;
		
		box.add(radio);

		foreach(var child in radio.get_children()){
			if (child is Gtk.Label){
				var label = (Gtk.Label) child;
				label.use_markup = true;
				break;
			}
		}
		
		return radio;
	}

	private Gtk.Button add_button(
		Gtk.Box box, string text, string tooltip,
		ref Gtk.SizeGroup? size_group,
		Gtk.Image? icon = null){
			
		var button = new Gtk.Button();
        box.add(button);

        button.set_label(text);
        button.set_tooltip_text(tooltip);

        if (icon != null){
			button.set_image(icon);
			button.set_always_show_image(true);
		}

		if (size_group == null){
			size_group = new Gtk.SizeGroup(SizeGroupMode.HORIZONTAL);
		}
		
		size_group.add_widget(button);
		
        return button;
	}
	
	private Gtk.Entry add_directory_chooser(Gtk.Box box, string selected_directory){
			
		// Entry
		var entry = new Gtk.Entry();
		entry.hexpand = true;
		entry.margin_left = 6;
		entry.secondary_icon_stock = "gtk-open";
		entry.placeholder_text = _("Enter path or browse for directory");
		box.add (entry);

		if ((selected_directory != null) && dir_exists(selected_directory)){
			entry.text = selected_directory;
		}

		entry.icon_release.connect((p0, p1) => {
			//chooser
			var chooser = new Gtk.FileChooserDialog(
			    _("Select Path"),
			    this,
			    FileChooserAction.SELECT_FOLDER,
			    "_Cancel",
			    Gtk.ResponseType.CANCEL,
			    "_Open",
			    Gtk.ResponseType.ACCEPT
			);

			chooser.select_multiple = false;
			chooser.set_filename(selected_directory);

			if (chooser.run() == Gtk.ResponseType.ACCEPT) {
				entry.text = chooser.get_filename();

				App.use_snapshot_path = true;
				App.snapshot_path = entry.text;
				
				if (!check_backup_location()){
					App.use_snapshot_path = false;
				}
			}

			chooser.destroy();
		});

		return entry;
	}
}