import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getAuth, signOut, onAuthStateChanged } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import { getDatabase, ref, onValue, onChildAdded, onChildChanged, onChildRemoved, get, set, push, remove, update, query, orderByChild, limitToLast } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-database.js";
import { firebaseConfig } from "./config.js";

// =========================================================================
// 1. SESSION GATE & CONFIG
// =========================================================================
// Baca sementara dari localStorage untuk tampilan awal topbar
// Nilai ini akan diverifikasi ulang secara aman dari database di onAuthStateChanged
let userRole = localStorage.getItem('user_role');
let userName = localStorage.getItem('user_name');
let userNrp = localStorage.getItem('user_nrp');
let userPangkat = localStorage.getItem('user_pangkat');
let userSatker = localStorage.getItem('user_satker');

function shouldFilterOutSatker(u) {
    // Default: do not filter client-side. Enforcement should be handled by Firebase rules.
    return false;
}

// NOTE: Do not redirect immediately based on cached localStorage. Wait for onAuthStateChanged
// to verify session and role from the server to avoid race conditions and tampering.

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getDatabase(app);

function logStreamError(msg, extra = {}) {
    try {
        if (typeof activePeerConnections !== 'undefined') {
            Object.keys(activePeerConnections).forEach(uid => {
                const conn = activePeerConnections[uid];
                if (conn && conn.viewerId) {
                    const errorRef = push(ref(db, `streams/${uid}/viewers/${conn.viewerId}/errors`));
                    set(errorRef, {
                        message: typeof msg === 'object' ? JSON.stringify(msg) : String(msg),
                        timestamp: Date.now(),
                        ...extra
                    });
                }
            });
        }
    } catch(e) {}
}

// Global error logging to Firebase for debugging remote connection issues
window.addEventListener('error', function(e) {
    logStreamError(e.message, {
        filename: e.filename,
        lineno: e.lineno,
        colno: e.colno,
        stack: e.error ? e.error.stack : '',
        type: 'uncaught-error'
    });
});

const originalConsoleError = console.error;
console.error = function(...args) {
    originalConsoleError.apply(console, args);
    logStreamError(args.map(arg => typeof arg === 'object' ? JSON.stringify(arg) : String(arg)).join(' '), {
        type: 'console.error'
    });
};

const originalConsoleWarn = console.warn;
console.warn = function(...args) {
    originalConsoleWarn.apply(console, args);
    logStreamError(args.map(arg => typeof arg === 'object' ? JSON.stringify(arg) : String(arg)).join(' '), {
        type: 'console.warn'
    });
};

// Runtime auth verification flag — set true after onAuthStateChanged confirms and syncs profile
window.authVerified = false;

function requireAuthVerified() {
    if (!window.authVerified) {
        alert('Sesi belum terverifikasi. Tunggu beberapa detik lalu coba lagi.', 'Peringatan', 'warning');
        return false;
    }
    return true;
}

function requireAdmin() {
    if (!requireAuthVerified()) return false;
    if (userRole !== 'admin') {
        alert('Akses ditolak: diperlukan hak Admin.', 'Akses Ditolak', 'danger');
        return false;
    }
    return true;
}

function requireCommanderOrAdmin() {
    if (!requireAuthVerified()) return false;
    if (userRole !== 'admin' && userRole !== 'commander') {
        alert('Akses ditolak: diperlukan hak Komandan atau Admin.', 'Akses Ditolak', 'danger');
        return false;
    }
    return true;
}

// Safety timeout: jika verifikasi sesi menggantung lebih dari 5 detik, tampilkan opsi keluar/masuk kembali
setTimeout(() => {
    const loadingOverlay = document.getElementById('authLoadingOverlay');
    if (loadingOverlay) {
        const loadingText = document.querySelector('#authLoadingOverlay p');
        const loadingSpinner = document.querySelector('#authLoadingOverlay .spinner-border');
        if (loadingText && loadingText.innerText.includes("Menghubungkan")) {
            loadingText.innerHTML = '<span class="text-danger">Sesi gagal diverifikasi atau koneksi terputus. <br><a href="#" id="btnForceLogout" class="btn btn-sm btn-outline-danger mt-3 fw-bold px-3 py-2" style="border-radius: 20px; font-size: 11px;">Keluar & Masuk Kembali</a></span>';
            if (loadingSpinner) {
                loadingSpinner.className = 'fa-solid fa-circle-exclamation text-danger mb-3';
                loadingSpinner.style.fontSize = '3rem';
            }

            setTimeout(() => {
                const btnForce = document.getElementById('btnForceLogout');
                if (btnForce) {
                        btnForce.addEventListener('click', (e) => {
                        e.preventDefault();
                        document.cookie = "session_active=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;";
                        localStorage.clear();
                        signOut(auth).then(() => {
                            window.location.href = "login.html";
                        }).catch(() => {
                            window.location.href = "login.html";
                        });
                    });
                }
            }, 100);
        }
    }
}, 5000);

// Proteksi Firebase Auth State & Verifikasi Profil Real-time
onAuthStateChanged(auth, (user) => {
    if (!user) {
        localStorage.clear();
        window.location.href = "login.html";
    } else {
        // Cek apakah cookie sesi aktif (jika tidak, ini adalah sesi browser baru dan user harus login ulang)
        if (!document.cookie.includes("session_active=true")) {
            console.log("[Auth] Browser session expired (no session cookie). Logging out.");
            localStorage.clear();
            window.authVerified = false;
            signOut(auth).then(() => { window.location.href = "login.html"; });
            return;
        }
        // Segera tampilkan dashboard - Firebase Auth sudah memverifikasi user
        window.authVerified = true;

        // Hilangkan loading overlay dan tampilkan dashboard SEKARANG
        const loadingOverlay = document.getElementById('authLoadingOverlay');
        if (loadingOverlay) {
            loadingOverlay.style.opacity = '0';
            setTimeout(() => { loadingOverlay.remove(); }, 300);
        }
        const wrapperEl = document.querySelector('.wrapper');
        if (wrapperEl) wrapperEl.style.display = 'flex';

        // Paksa Leaflet recalculate ukuran peta setelah container tampil
        setTimeout(() => {
            if (typeof map !== 'undefined') map.invalidateSize();
            if (typeof mapGeo !== 'undefined') mapGeo.invalidateSize();
        }, 350);

        // Verifikasi profil di background (tidak blokir UI)
        get(ref(db, 'users/' + user.uid)).then((snapshot) => {
            if (snapshot.exists()) {
                const data = snapshot.val();
                // Paksa logout jika akun tidak aktif atau bukan admin/commander
                if (data.status !== 'active' || (data.role !== 'admin' && data.role !== 'commander')) {
                    localStorage.clear();
                    window.authVerified = false;
                    signOut(auth).then(() => { window.location.href = "login.html"; });
                    return;
                }
                // Perbarui variabel runtime dengan data valid dari database
                userRole = data.role;
                userName = data.nama;
                userNrp = data.nrp;
                userPangkat = data.pangkat || '';
                userSatker = data.satker || 'Bid TIK';

                // Selaraskan perubahan profil dari DB ke local storage
                localStorage.setItem('user_role', data.role);
                localStorage.setItem('user_name', data.nama);
                localStorage.setItem('user_nrp', data.nrp);
                localStorage.setItem('user_pangkat', data.pangkat || '');
                localStorage.setItem('user_satker', data.satker || 'Bid TIK');

                // Update DOM Topbar secara dinamis dengan data valid terbaru
                const profNameEl = document.querySelector('.user-info h6');
                const profRoleEl = document.querySelector('.user-info small');
                const profImgEl = document.querySelector('.user-profile img');
                if (profNameEl) profNameEl.textContent = (data.pangkat || '') + ' ' + (data.nama || '');
                if (profRoleEl) profRoleEl.textContent = data.role.toUpperCase() + ' - ' + (data.satker || 'Bid TIK');
                if (profImgEl) profImgEl.src = `https://ui-avatars.com/api/?name=${encodeURIComponent(data.nama || '')}&background=0d6efd&color=fff&size=40`;

                // Role-based UI update setelah data profil tersedia
                if (data.role === 'commander') {
                    const el = document.querySelector('.topbar-title small');
                    if (el) el.textContent = 'Pusat Kendali Tim - ' + (data.satker || '');
                    const menuManajemen = document.getElementById('menu-manajemen');
                    const menuGeofence = document.getElementById('menu-geofence');
                    const menuPengaturan = document.getElementById('menu-pengaturan');
                    const menuApproval = document.getElementById('menu-approval');
                    const catAdmin = document.getElementById('cat-admin');
                    if (menuManajemen) menuManajemen.style.display = 'none';
                    if (menuGeofence) menuGeofence.style.display = 'none';
                    if (menuPengaturan) menuPengaturan.style.display = 'none';
                    if (menuApproval) menuApproval.style.display = 'none';
                    if (catAdmin) catAdmin.style.display = 'none';
                }
                // Init Live Chat UI, DM contacts, dan Live Ops listener setelah profil berhasil dimuat
                if (typeof initChatUI === 'function') initChatUI();
                if (typeof initChatListener === 'function') initChatListener();
                if (typeof loadContactList === 'function') loadContactList();
                if (typeof initLiveOpsListener === 'function') initLiveOpsListener();
            } else {
                // User terdaftar di Auth tapi tidak ada di database
                localStorage.clear();
                window.authVerified = false;
                signOut(auth).then(() => { window.location.href = "login.html"; });
            }
        }).catch((err) => {
            // Gagal fetch profil - tampilkan warning tapi JANGAN block UI
            // User tetap bisa menggunakan dashboard dengan data localStorage
            console.warn('Gagal fetch profil dari DB, menggunakan data cache:', err);
        });
    }
});

// Penanganan Logout
const handleLogout = (e) => {
    e.preventDefault();
    document.cookie = "session_active=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;";
    signOut(auth).then(() => {
        localStorage.clear();
        window.location.href = "login.html";
    });
};
const btnLogout = document.getElementById('btnLogout');
if (btnLogout) btnLogout.addEventListener('click', handleLogout);
const btnSidebarLogout = document.getElementById('btnSidebarLogout');
if (btnSidebarLogout) btnSidebarLogout.addEventListener('click', handleLogout);

// Update Informasi Profil di Topbar
if (userRole) {
    document.querySelector('.user-info h6').textContent = (userPangkat || "") + " " + (userName || "");
    document.querySelector('.user-info small').textContent = userRole.toUpperCase() + " - " + (userSatker || "");
    document.querySelector('.user-profile img').src = `https://ui-avatars.com/api/?name=${encodeURIComponent(userName || "")}&background=0d6efd&color=fff&size=40`;

    // Role-Based UI Customization
    if (userRole === 'commander') {
        document.querySelector('.topbar-title small').textContent = "Pusat Kendali Tim - " + userSatker;

        // Sembunyikan menu administrasi sistem untuk Komandan
        const menuManajemen = document.getElementById('menu-manajemen');
        const menuGeofence = document.getElementById('menu-geofence');
        const menuPengaturan = document.getElementById('menu-pengaturan');
        const menuApproval = document.getElementById('menu-approval');
        const catAdmin = document.getElementById('cat-admin');
        if (menuManajemen) menuManajemen.style.display = 'none';
        if (menuGeofence) menuGeofence.style.display = 'none';
        if (menuPengaturan) menuPengaturan.style.display = 'none';
        if (menuApproval) menuApproval.style.display = 'none';
        if (catAdmin) catAdmin.style.display = 'none';
    }

    if (userRole === 'member') {
        localStorage.clear();
        window.location.href = "login.html";
    }
}

// Penanganan Toggle Sidebar (Hamburger Menu)
const btnToggleSidebar = document.getElementById('btnToggleSidebar');
const sidebar = document.getElementById('sidebar');
if (sidebar && window.innerWidth < 768) {
    sidebar.classList.add('collapsed');
}
if (btnToggleSidebar) {
    btnToggleSidebar.addEventListener('click', () => {
        if (sidebar) {
            sidebar.classList.toggle('collapsed');
        }
    });
}

// Referensi Jalur Database
const refUsers = ref(db, 'users');
const refPesan = ref(db, 'messages');
const refGeofence = ref(db, 'geofences');
const refTracking = ref(db, 'live_tracking');

// =========================================================================
// CUSTOM MODAL ALERTS, CONFIRMS & PROFILE EDIT SYSTEM
// =========================================================================
window.alert = function (message, title = "Pemberitahuan", type = "success") {
    const alertModalEl = document.getElementById('customAlertModal');
    if (!alertModalEl) {
        console.warn("Custom alert modal not found, fallback to console:", message);
        return;
    }
    const alertTitle = document.getElementById('alertTitle');
    const alertMessage = document.getElementById('alertMessage');
    const alertIcon = document.getElementById('alertIcon');

    if (alertTitle) alertTitle.innerText = title;
    if (alertMessage) alertMessage.innerText = message;

    if (alertIcon) {
        alertIcon.className = "fa-solid";
        if (type === "success") {
            alertIcon.classList.add("fa-circle-check", "text-success");
        } else if (type === "warning") {
            alertIcon.classList.add("fa-triangle-exclamation", "text-warning");
        } else if (type === "danger") {
            alertIcon.classList.add("fa-circle-xmark", "text-danger");
        } else {
            alertIcon.classList.add("fa-circle-info", "text-primary");
        }
    }

    const modal = bootstrap.Modal.getOrCreateInstance(alertModalEl);
    modal.show();
};

window.showCustomConfirm = function (title, message, onConfirm, type = "warning") {
    const confirmModalEl = document.getElementById('customConfirmModal');
    if (!confirmModalEl) {
        if (confirm(message)) onConfirm();
        return;
    }

    const confirmTitle = document.getElementById('confirmTitle');
    const confirmMessage = document.getElementById('confirmMessage');
    const confirmIcon = document.getElementById('confirmIcon');
    const executeBtn = document.getElementById('btnCustomConfirmExecute');

    if (confirmTitle) confirmTitle.innerText = title;
    if (confirmMessage) confirmMessage.innerText = message;

    if (confirmIcon) {
        confirmIcon.className = "fa-solid";
        if (type === "warning") {
            confirmIcon.classList.add("fa-triangle-exclamation", "text-warning");
            executeBtn.className = "btn btn-danger px-4 fw-bold";
            executeBtn.innerText = "YA, EKSEKUSI";
        } else if (type === "danger") {
            confirmIcon.classList.add("fa-circle-xmark", "text-danger");
            executeBtn.className = "btn btn-danger px-4 fw-bold";
            executeBtn.innerText = "YA, HAPUS";
        } else {
            confirmIcon.classList.add("fa-circle-info", "text-primary");
            executeBtn.className = "btn btn-primary px-4 fw-bold";
            executeBtn.innerText = "YA, PROSES";
        }
    }

    const newExecuteBtn = executeBtn.cloneNode(true);
    executeBtn.parentNode.replaceChild(newExecuteBtn, executeBtn);

    const modal = bootstrap.Modal.getOrCreateInstance(confirmModalEl);

    newExecuteBtn.addEventListener('click', () => {
        modal.hide();
        onConfirm();
    });

    modal.show();
};

window.showCustomPrompt = function (title, label, defaultValue, onSubmit) {
    const promptModalEl = document.getElementById('customPromptModal');
    if (!promptModalEl) {
        const n = prompt(label, defaultValue);
        if (n) onSubmit(n);
        return;
    }

    const promptTitle = document.getElementById('promptTitle');
    const promptLabel = document.getElementById('promptLabel');
    const promptInput = document.getElementById('promptInputVal');
    const submitBtn = document.getElementById('btnCustomPromptSubmit');

    if (promptTitle) promptTitle.innerHTML = `<i class="fa-solid fa-map-location-dot text-primary me-2"></i> ${title}`;
    if (promptLabel) promptLabel.innerText = label;
    if (promptInput) {
        promptInput.value = defaultValue || '';
        setTimeout(() => promptInput.focus(), 500);
    }

    const newSubmitBtn = submitBtn.cloneNode(true);
    submitBtn.parentNode.replaceChild(newSubmitBtn, submitBtn);

    const modal = bootstrap.Modal.getOrCreateInstance(promptModalEl);

    newSubmitBtn.addEventListener('click', () => {
        const val = promptInput.value.trim();
        if (!val) {
            alert("Input tidak boleh kosong!", "Peringatan", "warning");
            return;
        }
        modal.hide();
        onSubmit(val);
    });

    modal.show();
};

window.bukaModalEdit = function (uid) {
    const u = localUsers[uid];
    if (!u) return;

    document.getElementById('edit-uid').value = uid;
    document.getElementById('edit-nrp').value = u.nrp || '';
    document.getElementById('edit-nama').value = u.nama || '';
    document.getElementById('edit-pangkat').value = u.pangkat || '';
    document.getElementById('edit-jabatan').value = u.jabatan || '';
    document.getElementById('edit-satker').value = u.satker || '';
    document.getElementById('edit-phone').value = u.no_hp_dinas || u.no_hp || '';

    // Set role dropdown
    const roleSelect = document.getElementById('edit-role');
    if (roleSelect) roleSelect.value = u.role || 'member';

    const modalEl = document.getElementById('editPersonelModal');
    const modal = bootstrap.Modal.getOrCreateInstance(modalEl);
    modal.show();
};

window.simpanEditPersonel = function () {
    if (!requireAdmin()) return;
    const uid = document.getElementById('edit-uid').value;
    if (!uid) return;

    const nama = document.getElementById('edit-nama').value.trim();
    const pangkat = document.getElementById('edit-pangkat').value.trim();
    const jabatan = document.getElementById('edit-jabatan').value.trim();
    const satker = document.getElementById('edit-satker').value.trim();
    const phone = document.getElementById('edit-phone').value.trim();
    const role = document.getElementById('edit-role') ? document.getElementById('edit-role').value : null;

    if (!nama || !pangkat || !jabatan || !satker || !phone) {
        alert("Semua field wajib diisi!", "Validasi Gagal", "warning");
        return;
    }

    const updates = {
        nama: nama,
        pangkat: pangkat,
        jabatan: jabatan,
        satker: satker,
        no_hp_dinas: phone,
        no_hp: phone
    };
    if (role) updates.role = role;

    update(ref(db, 'users/' + uid), updates).then(() => {
        const modalEl = document.getElementById('editPersonelModal');
        const modal = bootstrap.Modal.getInstance(modalEl);
        if (modal) modal.hide();
        alert("Data personel berhasil diperbarui!", "Berhasil", "success");
    }).catch(err => {
        alert("Gagal memperbarui data: " + err, "Error", "danger");
    });
};

// Bind Save action listener
document.addEventListener('DOMContentLoaded', () => {
    // Floating panels are now created and made draggable dynamically in createDynamicFloatingPanel

    const btnSimpanEdit = document.getElementById('btnSimpanEditPersonel');
    if (btnSimpanEdit) {
        btnSimpanEdit.addEventListener('click', window.simpanEditPersonel);
    }

    const btnExecuteCsvDownload = document.getElementById('btnExecuteCsvDownload');
    if (btnExecuteCsvDownload) {
        btnExecuteCsvDownload.addEventListener('click', window.prosesUnduhCSV);
    }

    const btnExecutePdfPrint = document.getElementById('btnExecutePdfPrint');
    if (btnExecutePdfPrint) {
        btnExecutePdfPrint.addEventListener('click', window.prosesCetakPDF);
    }

    // Reset page index on history filter change
    const filterStart = document.getElementById('filter-tanggal-mulai');
    if (filterStart) {
        filterStart.addEventListener('change', () => { currentPages.riwayat = 1; });
    }
    const filterEnd = document.getElementById('filter-tanggal-selesai');
    if (filterEnd) {
        filterEnd.addEventListener('change', () => { currentPages.riwayat = 1; });
    }
    const searchRiwayat = document.getElementById('search-riwayat');
    if (searchRiwayat) {
        searchRiwayat.addEventListener('keyup', () => { currentPages.riwayat = 1; });
    }

    const searchApproval = document.getElementById('search-approval');
    if (searchApproval) {
        searchApproval.addEventListener('keyup', () => { currentPages.approval = 1; });
    }

    const searchLaporan = document.getElementById('search-laporan');
    if (searchLaporan) {
        searchLaporan.addEventListener('keyup', () => { currentPages.laporan = 1; });
    }
    const lapStart = document.getElementById('laporan-tanggal-mulai');
    if (lapStart) {
        lapStart.addEventListener('change', () => { currentPages.laporan = 1; });
    }
    const lapEnd = document.getElementById('laporan-tanggal-selesai');
    if (lapEnd) {
        lapEnd.addEventListener('change', () => { currentPages.laporan = 1; });
    }

    // Bind settings changes to Firebase
    const setGps = document.getElementById('set-gps-interval');
    if (setGps) {
        setGps.addEventListener('change', (e) => {
            update(ref(db, 'system_settings'), { gps_interval: parseInt(e.target.value) });
        });
    }
    const setStale = document.getElementById('set-stale-timeout');
    if (setStale) {
        setStale.addEventListener('change', (e) => {
            update(ref(db, 'system_settings'), { stale_timeout: parseInt(e.target.value) });
        });
    }
    // SOS Sound settings listener removed
    // geofence sound switch listener removed
    const setMaint = document.getElementById('set-maintenance-mode');
    if (setMaint) {
        setMaint.addEventListener('change', (e) => {
            update(ref(db, 'system_settings'), { maintenance_mode: e.target.checked });
        });
    }
});

// =========================================================================
// GLOBAL STATE FOR ADVANCED FEATURES
// =========================================================================
let lastTrackingData = {};
let lastMemberGeofenceState = {};
let uniqueSatkers = new Set();
let localUsers = {};
let activeCountGlobal = 0;
let standbyCountGlobal = 0;

let currentPages = {
    manajemen: 1,
    operasi: 1,
    riwayat: 1,
    approval: 1,
    laporan: 1
};
let limitPages = {
    manajemen: 10,
    operasi: 10,
    riwayat: 10,
    approval: 10,
    laporan: 10
};

// Reusable Pagination Helper Function
window.setupPagination = function (tbodyId, allRows, currentPage, rowsPerPage, paginationContainerId, renderRowCallback) {
    const container = document.getElementById(paginationContainerId);
    if (!container) return;
    container.innerHTML = '';

    const totalRows = allRows.length;
    if (totalRows === 0) {
        container.style.display = 'none';
        return;
    }
    container.style.display = 'flex';

    const totalPages = Math.ceil(totalRows / rowsPerPage);
    const startIdx = (currentPage - 1) * rowsPerPage;
    const endIdx = Math.min(startIdx + rowsPerPage, totalRows);

    // 1. Pagination Info text & Limit Selector Wrapper
    const leftWrapper = document.createElement('div');
    leftWrapper.className = 'd-flex align-items-center gap-3 flex-wrap';

    const info = document.createElement('div');
    info.className = 'pagination-info';
    info.innerText = `Menampilkan ${startIdx + 1} - ${endIdx} dari ${totalRows} data`;
    leftWrapper.appendChild(info);

    // Dropdown limit select
    const key = tbodyId.replace('tbody-', '');
    const selectLimit = document.createElement('select');
    selectLimit.className = 'form-select form-select-sm';
    selectLimit.style.width = 'auto';
    selectLimit.style.borderRadius = '20px';
    selectLimit.style.fontSize = '11px';
    selectLimit.style.padding = '4px 10px';
    selectLimit.style.paddingRight = '24px';
    selectLimit.style.cursor = 'pointer';

    [10, 25, 50, 100].forEach(val => {
        const opt = document.createElement('option');
        opt.value = val;
        opt.innerText = `${val} Baris`;
        if (val === rowsPerPage) opt.selected = true;
        selectLimit.appendChild(opt);
    });

    selectLimit.onchange = (e) => {
        limitPages[key] = parseInt(e.target.value);
        currentPages[key] = 1; // Reset to page 1
        renderRowCallback();
    };
    leftWrapper.appendChild(selectLimit);

    container.appendChild(leftWrapper);

    // 2. Pagination controls wrapper
    const controls = document.createElement('div');
    controls.className = 'd-flex align-items-center gap-2';

    // Prev Button
    const btnPrev = document.createElement('button');
    btnPrev.type = 'button';
    btnPrev.className = 'pagination-btn';
    btnPrev.disabled = currentPage === 1;
    btnPrev.innerHTML = '<i class="fa-solid fa-chevron-left"></i> <span class="pagination-btn-text">SEBELUMNYA</span>';
    btnPrev.onclick = () => {
        const key = tbodyId.replace('tbody-', '');
        currentPages[key] = currentPage - 1;
        renderRowCallback();
    };
    controls.appendChild(btnPrev);

    // Page Numbers
    const pagesWrapper = document.createElement('div');
    pagesWrapper.className = 'pagination-pages';

    let startPage = Math.max(1, currentPage - 2);
    let endPage = Math.min(totalPages, startPage + 4);
    if (endPage - startPage < 4) {
        startPage = Math.max(1, endPage - 4);
    }

    for (let i = startPage; i <= endPage; i++) {
        const btnPage = document.createElement('div');
        btnPage.className = `pagination-page ${i === currentPage ? 'active' : ''}`;
        btnPage.innerText = i;
        btnPage.onclick = () => {
            const key = tbodyId.replace('tbody-', '');
            currentPages[key] = i;
            renderRowCallback();
        };
        pagesWrapper.appendChild(btnPage);
    }
    controls.appendChild(pagesWrapper);

    // Next Button
    const btnNext = document.createElement('button');
    btnNext.type = 'button';
    btnNext.className = 'pagination-btn';
    btnNext.disabled = currentPage === totalPages;
    btnNext.innerHTML = '<span class="pagination-btn-text">SELANJUTNYA</span> <i class="fa-solid fa-chevron-right"></i>';
    btnNext.onclick = () => {
        const key = tbodyId.replace('tbody-', '');
        currentPages[key] = currentPage + 1;
        renderRowCallback();
    };
    controls.appendChild(btnNext);

    container.appendChild(controls);
};

// Log Box Overlay Helpers
let logQueue = [];
const logContainer = document.getElementById('live-log-container');

function addCommLog(text, type = 'info') {
    const time = new Date().toLocaleTimeString('id-ID');
    let icon = 'fa-circle-info text-info';
    if (type === 'sos') icon = 'fa-triangle-exclamation text-danger fa-fade';
    if (type === 'geofence-enter') icon = 'fa-circle-right text-warning';
    if (type === 'geofence-exit') icon = 'fa-circle-left text-success';
    if (type === 'command') icon = 'fa-paper-plane text-primary';
    if (type === 'tracking') icon = 'fa-location-dot text-primary';

    logQueue.unshift({ time, text, icon });
    if (logQueue.length > 25) logQueue.pop(); // limit size

    if (logContainer) {
        logContainer.innerHTML = '';
        logQueue.forEach(log => {
            logContainer.innerHTML += `
                <div class="log-entry">
                    <span class="log-time">${log.time}</span>
                    <i class="fa-solid ${log.icon} me-1" style="font-size: 10px;"></i>
                    <span>${log.text}</span>
                </div>
            `;
        });
    }
}

// =========================================================================
// 2. JAM & TEMA
// =========================================================================
const currentTheme = localStorage.getItem('theme') || 'dark';
document.documentElement.setAttribute('data-theme', currentTheme);

// Initialize theme icon correctly
const themeIcon = document.getElementById('themeIcon');
if (themeIcon) {
    themeIcon.className = currentTheme === 'dark' ? 'fa-solid fa-sun' : 'fa-solid fa-moon';
}

document.getElementById('btnThemeToggle').addEventListener('click', () => {
    let newTheme = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', newTheme);
    localStorage.setItem('theme', newTheme);

    // Update theme icon dynamically
    const icon = document.getElementById('themeIcon');
    if (icon) {
        icon.className = newTheme === 'dark' ? 'fa-solid fa-sun' : 'fa-solid fa-moon';
    }

    // Update Leaflet tile layers dynamically without reloading page
    const newTileUrl = newTheme === 'dark'
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

    if (typeof mapTaktis !== 'undefined') mapTaktis.setUrl(newTileUrl);
    if (typeof mapGeoTaktis !== 'undefined') mapGeoTaktis.setUrl(newTileUrl);
});
function updateClock() {
    document.getElementById('clock').textContent = new Date().toLocaleTimeString('id-ID') + " WITA";
}
setInterval(updateClock, 1000);
updateClock();

// =========================================================================
// 3. LISTENERS DATABASE (REALTIME)
// =========================================================================

// A. Listener Data Pengguna (Manajemen & Approval)
let pendingUsersList = [];
window.renderApprovalTable = function () {
    const tbodyApproval = document.getElementById('tbody-approval');
    if (!tbodyApproval) return;
    tbodyApproval.innerHTML = '';

    const query = document.getElementById('search-approval') ? document.getElementById('search-approval').value.toLowerCase().trim() : '';
    let filteredPending = pendingUsersList;

    if (query) {
        filteredPending = pendingUsersList.filter(u =>
            (u.nrp && u.nrp.toLowerCase().includes(query)) ||
            (u.nama && u.nama.toLowerCase().includes(query)) ||
            (u.satker && u.satker.toLowerCase().includes(query)) ||
            (u.pangkat && u.pangkat.toLowerCase().includes(query))
        );
    }

    const page = currentPages.approval || 1;
    const limit = limitPages.approval;
    const startIdx = (page - 1) * limit;
    const endIdx = startIdx + limit;
    const pagedUsers = filteredPending.slice(startIdx, endIdx);

    if (pagedUsers.length === 0) {
        tbodyApproval.innerHTML = `<tr><td colspan="7" class="text-center text-muted py-4">Tidak ada pengajuan pendaftaran akun baru yang cocok.</td></tr>`;
    } else {
        pagedUsers.forEach(u => {
            tbodyApproval.innerHTML += `
                <tr>
                    <td><div class="fw-bold">${u.nrp}</div></td>
                    <td><div class="fw-bold">${u.nama}</div></td>
                    <td><div>${u.pangkat}</div><div class="text-muted small">${u.jabatan || '-'}</div></td>
                    <td>${u.satker}</td>
                    <td class="text-truncate" style="max-width: 150px;" title="${u.email || '-'}"><span class="font-monospace small">${u.email || '-'}</span></td>
                    <td>${u.waktu_daftar ? new Date(u.waktu_daftar).toLocaleString('id-ID') : '-'}</td>
                    <td class="text-center text-nowrap" style="text-align: center !important;">
                        <button class="btn btn-sm btn-success fw-bold me-2" onclick="prosesApproval('${u.uid}', true)"><i class="fa-solid fa-check me-1"></i> SETUJUI</button>
                        <button class="btn btn-sm btn-outline-danger fw-bold" onclick="prosesApproval('${u.uid}', false)"><i class="fa-solid fa-xmark me-1"></i> TOLAK</button>
                    </td>
                </tr>`;
        });
    }

    window.setupPagination('tbody-approval', filteredPending, page, limit, 'pagination-approval', window.renderApprovalTable);
};

onValue(refUsers, (snapshot) => {
    const data = snapshot.val();
    let pendingCount = 0;
    localUsers = {};
    uniqueSatkers.clear();
    pendingUsersList = [];

    if (data) {
        for (let uid in data) {
            let u = data[uid];
            localUsers[uid] = u;

            if (u.status === 'active') {
                uniqueSatkers.add(u.satker);
            }

            if (u.status === 'pending') {
                if (shouldFilterOutSatker(u)) {
                    continue;
                }
                pendingCount++;
                pendingUsersList.push({ ...u, uid });
            }
        }
    }

    const badgeApp = document.getElementById('badge-approval');
    if (badgeApp) {
        badgeApp.innerText = pendingCount;
        badgeApp.style.display = pendingCount > 0 ? 'inline-block' : 'none';
    }

    const titleBadgeApp = document.getElementById('title-badge-approval');
    if (titleBadgeApp) {
        titleBadgeApp.innerText = pendingCount;
        titleBadgeApp.style.display = pendingCount > 0 ? 'inline-block' : 'none';
    }

    updateSatkerDropdown();
    window.renderApprovalTable();
    applyFiltersAndRenderTable();
    updateChartsStats();
});

// Function to filter and render table + satker recap
window.applyFiltersAndRenderTable = function () {
    const query = document.getElementById('search-personel').value.toLowerCase();
    const selectedSatker = document.getElementById('filter-satker').value;
    const tbodyManajemen = document.getElementById('tbody-manajemen');
    if (!tbodyManajemen) return;

    tbodyManajemen.innerHTML = '';
    let activeUsersList = [];

    for (let uid in localUsers) {
        let u = localUsers[uid];
        if (u.status !== 'active') continue;
        if (shouldFilterOutSatker(u)) continue;

        if (selectedSatker && u.satker !== selectedSatker) continue;

        const text = `${u.nrp} ${u.nama} ${u.satker} ${u.pangkat} ${u.jabatan || ''}`.toLowerCase();
        if (query && !text.includes(query)) continue;

        activeUsersList.push({ ...u, uid });
    }

    const page = currentPages.manajemen || 1;
    const limit = limitPages.manajemen;
    const startIdx = (page - 1) * limit;
    const endIdx = startIdx + limit;
    const pagedUsers = activeUsersList.slice(startIdx, endIdx);

    if (pagedUsers.length === 0) {
        tbodyManajemen.innerHTML = `<tr><td colspan="7" class="text-center text-muted py-4">Tidak ada data personel aktif yang cocok.</td></tr>`;
    } else {
        pagedUsers.forEach(u => {
            let isOnDuty = false;
            if (lastTrackingData) {
                for (let trackKey in lastTrackingData) {
                    if (lastTrackingData[trackKey].nrp === u.nrp) {
                        isOnDuty = true;
                        break;
                    }
                }
            }

            let badgeColor = isOnDuty ? 'bg-success text-success border-success' : 'bg-secondary text-secondary border-secondary';
            let statusText = isOnDuty ? 'ON DUTY' : 'STANDBY';

            const actionHtml = userRole === 'admin'
                ? '<div class="d-inline-flex align-items-center justify-content-center gap-2 text-nowrap">'
                + '<button class="btn btn-sm btn-outline-primary" onclick="bukaModalEdit(\'' + u.uid + '\')"><i class="fa-solid fa-pen-to-square me-1"></i> Ubah</button>'
                + (u.nrp !== userNrp
                    ? '<button class="btn btn-sm btn-light border text-danger" onclick="hapusPersonel(\'' + u.uid + '\')"><i class="fa-solid fa-trash"></i> Hapus</button>'
                    : '<button class="btn btn-sm btn-light border text-muted" disabled title="Tidak dapat menghapus diri sendiri"><i class="fa-solid fa-trash"></i> Hapus</button>')
                + '</div>'
                : '-';

            tbodyManajemen.innerHTML += `
                <tr id="row-user-${u.nrp}">
                    <td class="fw-bold">${u.nrp}</td>
                    <td>
                        <div class="d-flex align-items-center gap-3">
                            <img src="https://ui-avatars.com/api/?name=${encodeURIComponent(u.nama)}&background=0d6efd&color=fff" class="rounded-circle" width="35">
                            <div><div class="fw-bold">${u.nama}</div></div>
                        </div>
                    </td>
                    <td>${u.pangkat} / ${u.jabatan || '-'}</td>
                    <td>${u.satker}</td>
                    <td class="text-center"><span class="badge bg-primary bg-opacity-10 text-primary border border-primary">${u.role === 'admin' ? 'ADMIN' : (u.role === 'commander' ? 'KOMANDAN' : 'ANGGOTA')}</span></td>
                    <td class="text-center"><span class="badge bg-opacity-10 border badge-custom status-badge-user ${badgeColor}" id="badge-user-${u.nrp}"><i class="fa-solid fa-circle me-1" style="font-size: 6px;"></i> ${statusText}</span></td>
                    <td class="text-center">${actionHtml}</td>
                </tr>`;
        });
    }

    const totalPersDash = document.getElementById('total-personnel-dash');
    if (totalPersDash) totalPersDash.innerText = activeUsersList.length;

    window.setupPagination('tbody-manajemen', activeUsersList, page, limit, 'pagination-manajemen', window.applyFiltersAndRenderTable);
    renderSatkerRecap();
};

// Update Satker Dropdown Options
function updateSatkerDropdown() {
    const satkerDropdown = document.getElementById('filter-satker');
    if (!satkerDropdown) return;

    const currentVal = satkerDropdown.value;
    satkerDropdown.innerHTML = '<option value="">Semua Satuan Kerja (Satker)</option>';

    uniqueSatkers.forEach(satker => {
        if (satker) {
            const opt = document.createElement('option');
            opt.value = satker;
            opt.innerText = satker;
            if (satker === currentVal) opt.selected = true;
            satkerDropdown.appendChild(opt);
        }
    });
}

// Render recap panels per satker
function renderSatkerRecap() {
    const recapContainer = document.getElementById('satker-recap-container');
    if (!recapContainer) return;
    recapContainer.innerHTML = '';

    let satkerStats = {};

    for (let uid in localUsers) {
        let u = localUsers[uid];
        if (u.status !== 'active') continue;
        if (shouldFilterOutSatker(u)) continue;

        if (!satkerStats[u.satker]) {
            satkerStats[u.satker] = { standby: 0, onDuty: 0, total: 0 };
        }

        let isOnDuty = false;
        if (lastTrackingData) {
            for (let trackKey in lastTrackingData) {
                if (lastTrackingData[trackKey].nrp === u.nrp) {
                    isOnDuty = true;
                    break;
                }
            }
        }

        if (isOnDuty) {
            satkerStats[u.satker].onDuty++;
        } else {
            satkerStats[u.satker].standby++;
        }
        satkerStats[u.satker].total++;
    }

    const satkers = Object.keys(satkerStats);
    if (satkers.length > 0) {
        satkers.forEach(satker => {
            const stats = satkerStats[satker];
            recapContainer.innerHTML += `
                <div class="col-lg-3 col-md-4 col-sm-6">
                    <div class="glass-card" style="padding: 12px 16px; border-bottom: 3px solid var(--primary);">
                        <div style="font-size: 10px; font-weight: 800; color: var(--text-muted); text-transform: uppercase; margin-bottom: 6px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;" title="${satker}">
                            ${satker}
                        </div>
                        <div class="d-flex justify-content-between align-items-center">
                            <span class="small text-muted" style="font-size: 11px;">Duty: <b class="text-success">${stats.onDuty}</b></span>
                            <span class="small text-muted" style="font-size: 11px;">Siaga: <b class="text-secondary">${stats.standby}</b></span>
                            <span class="badge bg-primary" style="font-size: 9px; border-radius: 12px;">${stats.total} Pers</span>
                        </div>
                    </div>
                </div>
            `;
        });
    }
}

// Set up listeners for filters
document.getElementById('filter-satker').addEventListener('change', () => {
    currentPages.manajemen = 1;
    applyFiltersAndRenderTable();
});
const searchPersonelEl = document.getElementById('search-personel');
if (searchPersonelEl) {
    searchPersonelEl.addEventListener('keyup', () => {
        currentPages.manajemen = 1;
        applyFiltersAndRenderTable();
    });
}

// Function to update Chart.js stats
function updateChartsStats() {
    let activeCount = 0;
    let standbyCount = 0;

    for (let uid in localUsers) {
        let u = localUsers[uid];
        if (u.status !== 'active') continue;
        if (shouldFilterOutSatker(u)) continue;

        let isOnDuty = false;
        if (lastTrackingData) {
            for (let trackKey in lastTrackingData) {
                if (lastTrackingData[trackKey].nrp === u.nrp) {
                    isOnDuty = true;
                    break;
                }
            }
        }

        if (isOnDuty) {
            activeCount++;
        } else {
            standbyCount++;
        }
    }

    activeCountGlobal = activeCount;
    standbyCountGlobal = standbyCount;

    initCharts(activeCountGlobal, standbyCountGlobal);
}

// B. Listener Pesan Komando
let isFirstMessageLoad = true;
onValue(refPesan, (snapshot) => {
    const data = snapshot.val();
    const container = document.getElementById('riwayat-pesan-container');
    if (!container) return;
    container.innerHTML = '';
    if (data) {
        const keys = Object.keys(data);
        keys.reverse().forEach(key => {
            let p = data[key];
            let warna = p.target.includes('ALL') ? 'primary' : 'warning';
            container.innerHTML += `
                <div class="border-start border-${warna} border-3 ps-3 mb-4">
                    <div class="d-flex justify-content-between align-items-center mb-1">
                        <span class="badge bg-${warna} bg-opacity-10 text-${warna} badge-custom">${p.target}</span>
                        <small class="text-muted" style="font-size: 11px;">${p.waktu}</small>
                    </div>
                    <p class="mb-0 text-main" style="font-size: 13px;">"${p.pesan}"</p>
                    <small class="text-muted fw-bold" style="font-size: 10px;">Oleh: ${p.oleh}</small>
                </div>`;
        });
        if (!isFirstMessageLoad && keys.length > 0) {
            const chronologicalKeys = Object.keys(data);
            const latestKey = chronologicalKeys[chronologicalKeys.length - 1];
            const p = data[latestKey];
            addCommLog(`Instruksi Taktis ke ${p.target}: "${p.pesan}" (oleh: ${p.oleh})`, 'command');
        }
    }
    isFirstMessageLoad = false;
});

// =========================================================================
// 4. OPERASI DATABASE
// =========================================================================
window.prosesApproval = function (uid, isAcc) {
    if (!requireAdmin()) return;
    if (isAcc) {
        window.showCustomConfirm("Setujui Pengajuan", "Apakah Anda yakin ingin menyetujui pengajuan pendaftaran akun ini?", () => {
            get(ref(db, 'users/' + uid)).then((snapshot) => {
                const u = snapshot.val();
                if (u) {
                    update(ref(db, 'users/' + uid), {
                        status: 'active'
                    }).then(() => {
                        if (u.email) {
                            const emailModal = new bootstrap.Modal(document.getElementById('emailApprovalModal'));
                            document.getElementById('modalEmailRecipient').value = u.email;
                            document.getElementById('modalEmailSubject').value = "Akun SIAGA Anda Telah Aktif";

                            const mailBody = `Yth. ${u.pangkat || ''} ${u.nama || ''},\n\nAkun SIAGA Anda dengan NRP ${u.nrp || ''} telah diverifikasi dan disetujui oleh Administrator.\n\nSilakan buka aplikasi SIAGA Mobile Tracker Anda untuk masuk ke sistem.\n\nSalam,\nBid TIK Polda Kalsel`;
                            document.getElementById('modalEmailBody').value = mailBody;

                            document.getElementById('btnCopyEmailText').onclick = () => {
                                navigator.clipboard.writeText(mailBody).then(() => {
                                    alert("Pesan pemberitahuan berhasil disalin ke clipboard!");
                                }).catch(err => {
                                    alert("Gagal menyalin teks: " + err);
                                });
                            };

                            document.getElementById('btnSendMailto').onclick = () => {
                                const subject = encodeURIComponent("Akun SIAGA Anda Telah Aktif");
                                const body = encodeURIComponent(mailBody);
                                window.open(`mailto:${u.email}?subject=${subject}&body=${body}`);
                            };

                            emailModal.show();
                        } else {
                            alert("Akun disetujui dan aktif!");
                        }
                    });
                }
            });
        }, "info");
    } else {
        window.showCustomConfirm("Tolak Pengajuan", "Apakah Anda yakin ingin menolak dan menghapus pengajuan pendaftaran akun ini?", () => {
            remove(ref(db, 'users/' + uid)).then(() => alert("Pendaftaran ditolak!"));
        }, "danger");
    }
};

window.ubahRole = function (uid, newRole) {
    if (!requireAdmin()) return;
    update(ref(db, 'users/' + uid), {
        role: newRole
    }).then(() => alert("Hak akses role diperbarui!"));
};

window.hapusPersonel = function (uid) {
    if (!requireAdmin()) return;
    get(ref(db, 'users/' + uid)).then((snapshot) => {
        const u = snapshot.val();
        const nrp = u ? u.nrp : 'Tidak diketahui';
        const email = (u && u.email) ? u.email : `${nrp}@siaga.polri.go.id`;

        const msg = `Apakah Anda yakin ingin menghapus akun (${nrp}) ini dari database?\n\n` +
            `⚠️ PENTING: Karena batasan keamanan Firebase client-side, Anda juga WAJIB menghapus akun login ini secara manual di Firebase Console > Build > Authentication > Users agar nomor/NRP ini dapat didaftarkan kembali.\n\n` +
            `Email Login untuk Dihapus: ${nrp}@siaga.polri.go.id`;

        window.showCustomConfirm("Hapus Akun Personel", msg, () => {
            remove(ref(db, 'users/' + uid)).then(() => {
                if (nrp) {
                    remove(ref(db, 'live_tracking/POL-' + nrp));
                }
                alert("Data akun berhasil dihapus dari database. Jangan lupa untuk menghapusnya dari tab Authentication di Firebase Console.");
            });
        }, "danger");
    });
};

window.kirimBroadcast = function () {
    if (!requireCommanderOrAdmin()) return;
    const pesan = document.getElementById('isi-broadcast').value;
    if (!pesan.trim()) return alert("Pesan kosong!");

    push(refPesan, {
        target: document.getElementById('target-broadcast').value,
        pesan: pesan,
        waktu: new Date().toLocaleTimeString('id-ID') + " WITA",
        oleh: userPangkat + " " + userName
    }).then(() => {
        document.getElementById('isi-broadcast').value = '';
        alert("Broadcast pesan terkirim!");
    });
};

// =========================================================================
// 5. PETA & GEOFENCE INTERAKTIF (LEAFLET JS)
// =========================================================================

// Base layers for main Map
const mapTaktis = L.tileLayer(currentTheme === 'dark' ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png' : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
    attribution: '&copy; CARTO'
});
const mapOSM = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors'
});
const mapSatelit = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
    attribution: 'Tiles &copy; Esri &mdash; Source: Esri'
});

const baseMaps = {
    "<span class='text-muted small fw-bold'><i class='fa-solid fa-map me-1'></i> Leaflet (Taktis)</span>": mapTaktis,
    "<span class='text-muted small fw-bold'><i class='fa-solid fa-route me-1'></i> OpenStreetMap</span>": mapOSM,
    "<span class='text-muted small fw-bold'><i class='fa-solid fa-globe me-1'></i> ESRI World Imagery</span>": mapSatelit
};

const map = L.map('map', { zoomControl: false }).setView([-3.4428, 114.8306], 13);

// Set default tile base according to current theme
mapTaktis.addTo(map);

// Add map switcher control to bottom-right first
L.control.layers(baseMaps, null, { position: 'bottomright' }).addTo(map);

// Add zoom control second (stacks above the layers control)
L.control.zoom({ position: 'bottomright' }).addTo(map);

// Base layers for Geofence Map
const mapGeoTaktis = L.tileLayer(currentTheme === 'dark' ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png' : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
    attribution: '&copy; CARTO'
});
const mapGeoOSM = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors'
});
const mapGeoSatelit = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
    attribution: 'Tiles &copy; Esri'
});

const baseMapsGeo = {
    "<span class='text-muted small fw-bold'><i class='fa-solid fa-map me-1'></i> Leaflet (Taktis)</span>": mapGeoTaktis,
    "<span class='text-muted small fw-bold'><i class='fa-solid fa-route me-1'></i> OpenStreetMap</span>": mapGeoOSM,
    "<span class='text-muted small fw-bold'><i class='fa-solid fa-globe me-1'></i> ESRI World Imagery</span>": mapGeoSatelit
};

const mapGeo = L.map('map-geofence', { zoomControl: false }).setView([-3.4428, 114.8306], 12);

mapGeoTaktis.addTo(mapGeo);

// Add map switcher control to bottom-right first
L.control.layers(baseMapsGeo, null, { position: 'bottomright' }).addTo(mapGeo);

// Add zoom control second (stacks above layers control)
L.control.zoom({ position: 'bottomright' }).addTo(mapGeo);

const cIcon = L.divIcon({ className: 'custom-div-icon', html: '<div style="background-color:#ef4444; width:16px; height:16px; border-radius:50%; border:3px solid white; cursor:move; box-shadow: 0 2px 8px rgba(0,0,0,0.3)"></div>', iconSize: [16, 16] });
const eIcon = L.divIcon({ className: 'custom-div-icon', html: '<div style="background-color:white; width:14px; height:14px; border:3px solid #ef4444; border-radius:3px; cursor:ew-resize; box-shadow: 0 2px 8px rgba(0,0,0,0.3)"></div>', iconSize: [14, 14] });
let centerMarker = L.marker([-3.4428, 114.8306], { draggable: true, icon: cIcon }).addTo(mapGeo);
let edgeMarker = L.marker([-3.4428, 114.8606], { draggable: true, icon: eIcon }).addTo(mapGeo);

let zones = {};
let activeZoneKey = null;
let markerGroup = L.markerClusterGroup({ disableClusteringAtZoom: 18 }).addTo(map);

function calcEdge(center, r) {
    return L.latLng(center.lat, center.lng + (r / (6378137 * Math.cos(Math.PI * center.lat / 180))) * 180 / Math.PI);
}

// Helper function to resolve dynamic vehicle icons
function getVehicleIconClass(vehicle) {
    if (!vehicle) return 'fa-person-military-pointing';
    const v = vehicle.toLowerCase().trim();

    if (v.includes('jalan kaki') || v.includes('jalan') || v.includes('kaki') || v.includes('pedestrian')) {
        return 'fa-person-military-pointing'; // Jalan Kaki
    }
    if (v.includes('motor') || v.includes('trail') || v.includes('r2') || v.includes('roda 2') || v.includes('dua')) {
        return 'fa-motorcycle'; // Sepeda Motor
    }
    if (v.includes('bus') || v.includes('bis')) {
        return 'fa-bus'; // Bus
    }
    if (v.includes('truk') || v.includes('truck') || v.includes('dalmas') || v.includes('water cannon') || v.includes('box')) {
        return 'fa-truck'; // Truk
    }
    if (v.includes('mobil') || v.includes('car') || v.includes('r4') || v.includes('roda 4') || v.includes('sedan') || v.includes('patroli') || v.includes('dinas') || v.includes('pajero') || v.includes('triton')) {
        return 'fa-car-on'; // Mobil
    }
    // "Lainnya" (Mobil taktis, sound, senjata, armor, helikopter, kapal, dll.)
    return 'fa-shield-halved';
}

// BACA LIVE TRACKING GPS PERSONEL
let activeOperationsList = [];
window.renderOperationsTable = function () {
    const tbodyOperasi = document.getElementById('tbody-operasi');
    if (!tbodyOperasi) return;
    tbodyOperasi.innerHTML = '';

    const page = currentPages.operasi || 1;
    const limit = limitPages.operasi;
    const startIdx = (page - 1) * limit;
    const endIdx = startIdx + limit;
    const pagedOps = activeOperationsList.slice(startIdx, endIdx);

    if (pagedOps.length === 0) {
        tbodyOperasi.innerHTML = `<tr><td colspan="8" class="text-center text-muted py-4">Tidak ada operasi aktif saat ini.</td></tr>`;
    } else {
        pagedOps.forEach(u => {
            let userProfile = Object.values(localUsers).find(user => user.nrp === u.nrp);
            let noHp = u.no_hp || (userProfile ? userProfile.no_hp_dinas : '') || '';
            const waNoHp = noHp ? noHp.replace(/\D/g, '').replace(/^0/, '62') : '';
            const contactHtml = noHp
                ? '<a href="https://wa.me/' + waNoHp + '" target="_blank" class="btn btn-sm btn-success fw-bold me-1 text-white font-monospace" title="Hubungi via WhatsApp"><i class="fa-brands fa-whatsapp me-1"></i> ' + noHp + '</a><a href="tel:' + noHp + '" class="btn btn-sm btn-outline-success fw-bold me-1 font-monospace" title="Panggilan Telepon"><i class="fa-solid fa-phone"></i></a>'
                : '<button class="btn btn-sm btn-secondary fw-bold me-1 font-monospace" disabled><i class="fa-solid fa-phone-slash me-1"></i> -</button>';

            tbodyOperasi.innerHTML += `
                <tr>
                    <td class="text-nowrap"><span class="badge bg-primary bg-opacity-10 text-primary border border-primary font-monospace">${u.op_code || 'OPS-SIAGA-001'}</span></td>
                    <td><div class="fw-bold">${u.jenis_giat || 'Pengamanan Wilayah'}</div><div class="text-muted small">${u.description || 'Pengamanan Taktis'}</div></td>
                    <td class="text-nowrap">${u.commander || 'Mandiri'}</td>
                    <td class="text-nowrap">${u.satker}</td>
                    <td class="text-nowrap"><span class="badge bg-success bg-opacity-10 text-success border border-success"><i class="fa-solid fa-circle-play fa-fade me-1"></i> AKTIF</span></td>
                    <td class="text-nowrap">
                        <div class="fw-bold">${u.pangkat || ''} ${u.nama}</div>
                        <div class="text-muted small">NRP: ${u.nrp} | ${u.vehicle || 'Roda 4'}</div>
                    </td>
                    <td class="text-nowrap">${u.waktu ? new Date(u.waktu).toLocaleTimeString('id-ID') + ' WITA' : '-'}</td>
                    <td class="text-center text-nowrap" style="text-align: center !important;">
                        ${contactHtml}
                        <button class="btn btn-sm btn-outline-primary fw-bold" onclick="focusActiveUnit(${u.koordinat.lat}, ${u.koordinat.lng})"><i class="fa-solid fa-location-dot"></i> PETA</button>
                    </td>
                </tr>
            `;
        });
    }

    window.setupPagination('tbody-operasi', activeOperationsList, page, limit, 'pagination-operasi', window.renderOperationsTable);
};

// Simpan snapshot data tracking agar bisa diredraw sewaktu-waktu (misal saat info stream berubah)
window.lastTrackingSnapshotData = null;

window.redrawMapMarkers = function () {
    const data = window.lastTrackingSnapshotData;
    markerGroup.clearLayers();
    let activeUnitCount = 0;

    document.querySelectorAll('.status-badge-user').forEach(badge => {
        badge.className = "badge bg-opacity-10 border badge-custom status-badge-user bg-secondary text-secondary border-secondary";
        badge.innerHTML = `<i class="fa-solid fa-circle me-1" style="font-size: 6px;"></i> STANDBY`;
    });

    activeOperationsList = [];
    let opCodes = new Set();

    if (data) {
        for (let key in data) {
            let u = data[key];

            if (shouldFilterOutSatker(u)) {
                continue;
            }

            activeUnitCount++;
            opCodes.add(u.op_code || 'OPS-SIAGA-001');

            const badgeElement = document.getElementById(`badge-user-${u.nrp}`);
            if (badgeElement) {
                badgeElement.className = "badge bg-opacity-10 border badge-custom status-badge-user bg-success text-success border-success";
                badgeElement.innerHTML = `<i class="fa-solid fa-circle me-1" style="font-size: 6px;"></i> ON DUTY`;
            }

            // Push to operations list for table rendering
            activeOperationsList.push(u);

            // Render to Map
            if (u.koordinat && u.koordinat.lat && u.koordinat.lng) {
                const vehicleIconClass = getVehicleIconClass(u.vehicle);

                // Check if user is live streaming
                const activeStreamInfo = typeof activeStreams !== 'undefined' ? Object.values(activeStreams).find(s => s.nrp === u.nrp) : null;
                const isStreaming = activeStreamInfo !== null && activeStreamInfo !== undefined;
                const streamerUid = isStreaming ? activeStreamInfo.uid : null;

                let markerIcon = L.divIcon({
                    className: `police-marker ${isStreaming ? 'streaming-marker-icon' : ''}`,
                    html: `<div class="marker-icon-wrapper active-glow ${isStreaming ? 'pulse-red' : ''}" style="background-color: ${isStreaming ? '#ef4444' : 'var(--primary)'}">
                            <i class="fa-solid ${isStreaming ? 'fa-tower-broadcast' : vehicleIconClass}"></i>
                           </div>`,
                    iconSize: [36, 36],
                    iconAnchor: [18, 18]
                });

                const waNumber = u.no_hp ? u.no_hp.replace(/\D/g, '').replace(/^0/, '62') : '';
                const unitFullName = ((u.pangkat || '').trim() + ' ' + u.nama).trim();
                const popupNoHp = u.no_hp ? [
                    '<div class="mt-2 d-flex gap-1">',
                    '<a href="https://wa.me/' + waNumber + '" target="_blank" class="btn btn-xs btn-success fw-bold text-white w-100 font-monospace" style="font-size: 10px; padding: 4px;"><i class="fa-brands fa-whatsapp me-1"></i> WA</a>',
                    '<a href="tel:' + u.no_hp + '" class="btn btn-xs btn-outline-success fw-bold w-100 font-monospace" style="font-size: 10px; padding: 4px;"><i class="fa-solid fa-phone me-1"></i> Telp</a>',
                    '</div>'
                ].join('') : '';
                const popupLive = isStreaming ? '<button class="btn btn-xs btn-danger fw-bold text-white w-100 mt-2 font-monospace" style="font-size: 10px; padding: 4px;" onclick="window.watchLiveStream(\'' + streamerUid + '\', \'' + unitFullName + '\')"><i class="fa-solid fa-tower-broadcast me-1"></i> TONTON LIVE</button>' : '';

                let m = L.marker([u.koordinat.lat, u.koordinat.lng], { icon: markerIcon });
                m.bindPopup(`
                    <div style="font-family: 'Inter', sans-serif; padding: 5px; min-width: 200px;">
                        <h6 class="fw-bold mb-0" style="color: var(--text-main); font-size: 13px;">${unitFullName}</h6>
                        <p class="mb-2 text-muted" style="font-size: 10px;">NRP: ${u.nrp} | ${u.satker}</p>
                        <hr style="margin: 6px 0; border-color: var(--border-color);">
                        <div class="d-flex justify-content-between mb-1" style="font-size: 11px;"><span>Aktivitas:</span> <b class="text-primary">${u.jenis_giat || 'Pengamanan'}</b></div>
                        <div class="d-flex justify-content-between mb-1" style="font-size: 11px;"><span>Kendaraan:</span> <b>${u.vehicle || '-'}</b></div>
                        <div class="d-flex justify-content-between mb-1" style="font-size: 11px;"><span>Komandan:</span> <b>${u.commander || 'Mandiri'}</b></div>
                        <div class="d-flex justify-content-between mb-1" style="font-size: 11px;"><span>Kekuatan:</span> <b>${u.jumlah_personel || 1} Anggota</b></div>
                        <div class="d-flex justify-content-between mb-1" style="font-size: 11px;"><span>Akurasi GPS:</span> <b>${u.koordinat.akurasi ? Math.round(u.koordinat.akurasi) + ' m' : '-'}</b></div>
                        <div class="d-flex justify-content-between mb-2" style="font-size: 11px;"><span>Update:</span> <b class="text-success">${new Date(u.waktu).toLocaleTimeString('id-ID')} WITA</b></div>
                        ${popupNoHp}
                        ${popupLive}
                    </div>
                `);
                markerGroup.addLayer(m);
            }
        }
    }

    window.renderOperationsTable();

    const totUnitEl = document.getElementById('total-unit');
    if (totUnitEl) totUnitEl.innerText = activeUnitCount;

    const totalOpEl = document.getElementById('total-operation');
    if (totalOpEl) totalOpEl.innerText = opCodes.size;

    applyFiltersAndRenderTable();
    updateChartsStats();
};

onValue(refTracking, (snapshot) => {
    const data = snapshot.val();

    // Online/Offline & Geofence detection
    let freshTracking = data || {};

    for (let key in freshTracking) {
        const u = freshTracking[key];
        if (!lastTrackingData[key]) {
            addCommLog(`${u.pangkat || ''} ${u.nama} (NRP: ${u.nrp}) mulai tugas / aktif`, 'tracking');
        }
    }
    for (let key in lastTrackingData) {
        if (!freshTracking[key]) {
            const u = lastTrackingData[key];
            addCommLog(`${u.pangkat || ''} ${u.nama} (NRP: ${u.nrp}) selesai tugas / standby`, 'tracking');
            if (lastMemberGeofenceState[u.nrp]) {
                delete lastMemberGeofenceState[u.nrp];
            }
        }
    }

    for (let key in freshTracking) {
        const u = freshTracking[key];
        if (u.koordinat && u.koordinat.lat && u.koordinat.lng) {
            const userLatLng = L.latLng(u.koordinat.lat, u.koordinat.lng);
            if (!lastMemberGeofenceState[u.nrp]) {
                lastMemberGeofenceState[u.nrp] = {};
            }
            for (let zoneKey in zones) {
                const zone = zones[zoneKey];
                if (zone.aktif === false) continue;
                const zoneLatLng = L.latLng(zone.lat, zone.lng);
                const dist = userLatLng.distanceTo(zoneLatLng);
                const isInside = dist <= zone.radius;
                const wasInside = lastMemberGeofenceState[u.nrp][zoneKey] === true;

                if (isInside && !wasInside) {
                    addCommLog(`ALERT: ${u.pangkat || ''} ${u.nama} (NRP: ${u.nrp}) MASUK Zona Merah: "${zone.nama}"`, 'geofence-enter');
                    lastMemberGeofenceState[u.nrp][zoneKey] = true;
                } else if (!isInside && wasInside) {
                    addCommLog(`INFO: ${u.pangkat || ''} ${u.nama} (NRP: ${u.nrp}) KELUAR dari Zona Merah: "${zone.nama}"`, 'geofence-exit');
                    lastMemberGeofenceState[u.nrp][zoneKey] = false;
                }
            }
        }
    }

    lastTrackingData = freshTracking;

    if (data) {
        for (let key in data) {
            let u = data[key];
            if (u.waktu) {
                const updateTime = new Date(u.waktu);
                const now = new Date();
                const diffMs = now - updateTime;
                const diffMins = diffMs / 1000 / 60;
                const staleThreshold = window.systemSettings?.stale_timeout || 15;
                if (diffMins > staleThreshold) {
                    remove(ref(db, 'live_tracking/' + key));
                    continue;
                }
            }
        }
    }

    window.lastTrackingSnapshotData = data;
    window.redrawMapMarkers();
});

// Focus active unit from table
window.focusActiveUnit = function (lat, lng) {
    map.setView([lat, lng], 15);
    switchPage('peta', document.getElementById('menu-peta'));
};

// BACA ZONA MERAH GEOFENCE
onValue(refGeofence, (snapshot) => {
    const data = snapshot.val();

    for (let key in zones) {
        map.removeLayer(zones[key].mapCircle);
        mapGeo.removeLayer(zones[key].geoCircle);
    }
    zones = {};

    // Hapus marker kalibrasi terlebih dahulu untuk menghindari penumpukan atau penundaan (lingering markers)
    if (mapGeo.hasLayer(centerMarker)) mapGeo.removeLayer(centerMarker);
    if (mapGeo.hasLayer(edgeMarker)) mapGeo.removeLayer(edgeMarker);

    let count = 0;

    if (data) {
        for (let key in data) {
            let z = data[key];
            count++;
            let isActive = z.aktif !== false;
            let zoneColor = isActive ? '#ef4444' : '#6b7280';

            // Lebih transparan dan border lebih tipis agar premium
            let cGeo = L.circle([z.lat, z.lng], {
                color: zoneColor,
                weight: 1.5,
                opacity: 0.6,
                fillColor: zoneColor,
                fillOpacity: 0.08,
                radius: z.radius
            }).addTo(mapGeo);

            let cLive = L.circle([z.lat, z.lng], {
                color: zoneColor,
                weight: 1.5,
                opacity: 0.5,
                fillColor: zoneColor,
                fillOpacity: 0.04,
                radius: z.radius,
                interactive: false
            }).addTo(map);

            zones[key] = { nama: z.nama, mapCircle: cLive, geoCircle: cGeo, lat: z.lat, lng: z.lng, radius: z.radius, aktif: isActive };

            cGeo.on('click', () => { window.setActiveZone(key); });
        }
    }

    // Validasi agar activeZoneKey tidak tersangkut di key yang sudah didelete
    if (activeZoneKey && !zones[activeZoneKey]) {
        activeZoneKey = null;
    }

    // Jika tidak ada activeZoneKey tapi ada zona tersedia, set ke zona pertama
    if (!activeZoneKey && Object.keys(zones).length > 0) {
        activeZoneKey = Object.keys(zones)[0];
    }

    // Tampilkan marker & perbarui UI jika ada zona aktif
    if (activeZoneKey && zones[activeZoneKey]) {
        let z = zones[activeZoneKey];
        let pos = L.latLng(z.lat, z.lng);
        centerMarker.setLatLng(pos);
        edgeMarker.setLatLng(calcEdge(pos, z.radius));

        centerMarker.addTo(mapGeo);
        edgeMarker.addTo(mapGeo);

        updateGeoUI(pos, z.radius);

        const actZoneLabel = document.getElementById('label-zona-aktif');
        if (actZoneLabel) actZoneLabel.innerText = z.nama;

        const zoneNameInput = document.getElementById('input-zona-nama');
        if (zoneNameInput) zoneNameInput.value = z.nama;

        const statusCheck = document.getElementById('input-geofence-status');
        if (statusCheck) {
            statusCheck.checked = (z.aktif !== false);
        }

        const btnHapus = document.getElementById('btn-hapus-zona');
        if (btnHapus) btnHapus.style.display = 'block';
    } else {
        // Jika semua zona dihapus, kosongkan form input & sembunyikan tombol hapus
        const actLabel = document.getElementById('label-zona-aktif');
        if (actLabel) actLabel.innerText = "-";

        const latInp = document.getElementById('input-lat');
        const lngInp = document.getElementById('input-lng');
        const radInp = document.getElementById('input-radius');
        const radVal = document.getElementById('radius-val');
        if (latInp) latInp.value = "";
        if (lngInp) lngInp.value = "";
        if (radInp) radInp.value = "2500";
        if (radVal) radVal.innerText = "0 m";

        const zoneNameInput = document.getElementById('input-zona-nama');
        if (zoneNameInput) zoneNameInput.value = "";

        const btnHapus = document.getElementById('btn-hapus-zona');
        if (btnHapus) btnHapus.style.display = 'none';
    }

    const dashGeoCount = document.getElementById('dash-geo-count');
    if (dashGeoCount) dashGeoCount.innerText = count;
});

window.setActiveZone = function (key) {
    activeZoneKey = key;
    let z = zones[key];
    if (!z) return;

    for (let k in zones) {
        let isActiveK = zones[k].aktif !== false;
        let colorK = isActiveK ? '#ef4444' : '#6b7280';
        zones[k].geoCircle.setStyle({ color: colorK, fillColor: colorK });
    }

    let isActive = z.aktif !== false;
    let activeColor = isActive ? '#ef4444' : '#6b7280';
    z.geoCircle.setStyle({ color: activeColor, fillColor: activeColor });

    let pos = L.latLng(z.lat, z.lng);
    centerMarker.setLatLng(pos);
    edgeMarker.setLatLng(calcEdge(pos, z.radius));

    if (!mapGeo.hasLayer(centerMarker)) centerMarker.addTo(mapGeo);
    if (!mapGeo.hasLayer(edgeMarker)) edgeMarker.addTo(mapGeo);

    updateGeoUI(pos, z.radius);

    const actZoneLabel = document.getElementById('label-zona-aktif');
    if (actZoneLabel) actZoneLabel.innerText = z.nama;

    const zoneNameInput = document.getElementById('input-zona-nama');
    if (zoneNameInput) zoneNameInput.value = z.nama;

    const statusCheck = document.getElementById('input-geofence-status');
    if (statusCheck) {
        statusCheck.checked = isActive;
    }

    const btnHapus = document.getElementById('btn-hapus-zona');
    if (btnHapus) btnHapus.style.display = 'block';
};

function updateGeoUI(latlng, r) {
    const latInp = document.getElementById('input-lat');
    const lngInp = document.getElementById('input-lng');
    const radInp = document.getElementById('input-radius');
    const radVal = document.getElementById('radius-val');

    if (latInp) latInp.value = latlng.lat.toFixed(6);
    if (lngInp) lngInp.value = latlng.lng.toFixed(6);
    if (radInp) radInp.value = Math.round(r);
    if (radVal) radVal.innerText = Math.round(r) + " m";

    if (activeZoneKey && zones[activeZoneKey]) {
        zones[activeZoneKey].geoCircle.setLatLng(latlng);
        zones[activeZoneKey].geoCircle.setRadius(r);
    }
}

// Marker Dragging (Dioptimalkan agar sangat lancar tanpa lag/fighting)
centerMarker.on('drag', function (e) {
    updateGeoUI(e.latlng, document.getElementById('input-radius').value);
    edgeMarker.setLatLng(calcEdge(e.latlng, document.getElementById('input-radius').value));
});
edgeMarker.on('drag', function (e) {
    let c = centerMarker.getLatLng();
    let r = c.distanceTo(e.latlng);
    if (r < 500) r = 500;
    updateGeoUI(c, r);
    // Jangan setLatLng ke edgeMarker ketika sedang drag agar tidak konflik dengan state internal Leaflet
});
edgeMarker.on('dragend', function (e) {
    let c = centerMarker.getLatLng();
    let r = c.distanceTo(edgeMarker.getLatLng());
    if (r < 500) r = 500;
    edgeMarker.setLatLng(calcEdge(c, r)); // Rapikan/kunci posisi di garis timur horizontal setelah selesai drag
});
const radInp = document.getElementById('input-radius');
if (radInp) {
    radInp.addEventListener('input', function (e) {
        let r = e.target.value;
        updateGeoUI(centerMarker.getLatLng(), r);
        edgeMarker.setLatLng(calcEdge(centerMarker.getLatLng(), r));
    });
}

window.simpanZonaFirebase = function () {
    if (!requireAdmin()) return;
    if (!activeZoneKey) return;
    const statusCheck = document.getElementById('input-geofence-status');
    const isAktif = statusCheck ? statusCheck.checked : true;

    const zoneNameInput = document.getElementById('input-zona-nama');
    const zoneName = zoneNameInput ? zoneNameInput.value.trim() : document.getElementById('label-zona-aktif').innerText;
    if (!zoneName) return alert("Nama Zona tidak boleh kosong!");

    set(ref(db, 'geofences/' + activeZoneKey), {
        nama: zoneName,
        lat: parseFloat(document.getElementById('input-lat').value),
        lng: parseFloat(document.getElementById('input-lng').value),
        radius: parseInt(document.getElementById('input-radius').value),
        aktif: isAktif
    }).then(() => {
        alert("Batas Zona Merah Berhasil Diperbarui!");
        document.getElementById('label-zona-aktif').innerText = zoneName;
    });
};

window.tambahZonaBaru = function () {
    if (!requireAdmin()) return;
    window.showCustomPrompt("Tambah Zona Baru", "Nama Zona Baru:", "", (n) => {
        // Cari posisi yang tidak bertabrakan dengan zona yang sudah ada
        // Mulai dari tengah peta, lalu geser sampai tidak overlap dengan zona existing
        const center = mapGeo.getCenter();
        const newRadius = 2500;
        let targetLat = center.lat;
        let targetLng = center.lng;

        // Coba berbagai posisi offset hingga menemukan yang tidak overlap
        const offsets = [
            [0.025, 0.000], [-0.025, 0.000], [0.000, 0.030], [0.000, -0.030],
            [0.025, 0.030], [-0.025, 0.030], [0.025, -0.030], [-0.025, -0.030],
            [0.050, 0.000], [-0.050, 0.000], [0.000, 0.060], [0.000, -0.060]
        ];

        let placed = false;
        for (let [dLat, dLng] of offsets) {
            const candidateLat = center.lat + dLat;
            const candidateLng = center.lng + dLng;
            const candidateLL = L.latLng(candidateLat, candidateLng);

            // Cek apakah kandidat posisi overlap dengan zona yang sudah ada
            let overlaps = false;
            for (let key in zones) {
                const z = zones[key];
                const existingLL = L.latLng(z.lat, z.lng);
                const distance = candidateLL.distanceTo(existingLL);
                if (distance < (newRadius + z.radius + 500)) { // 500m buffer
                    overlaps = true;
                    break;
                }
            }

            if (!overlaps) {
                targetLat = candidateLat;
                targetLng = candidateLng;
                placed = true;
                break;
            }
        }

        // Kalau semua offset overlap, gunakan posisi terakhir dengan random jitter
        if (!placed) {
            targetLat = center.lat + (0.06 + Math.random() * 0.03);
            targetLng = center.lng + (0.06 + Math.random() * 0.03);
        }

        push(refGeofence, { nama: n, lat: targetLat, lng: targetLng, radius: newRadius, aktif: true });
    });
};

window.hapusZonaFirebase = function () {
    if (!requireAdmin()) return;
    if (!activeZoneKey) return alert("Pilih zona yang ingin dihapus!");
    window.showCustomConfirm("Hapus Zona Taktis", "Apakah Anda yakin ingin menghapus zona ini secara permanen?", () => {
        const keyToDelete = activeZoneKey;
        activeZoneKey = null; // Reset state agar tidak ada penundaan visual
        remove(ref(db, 'geofences/' + keyToDelete));
    }, "danger");
};

// =========================================================================
// 6. REALTIME EMERGENCY SOS ALERTS (REMOVED)
// =========================================================================
// SOS emergency alert listener and audio siren sound features have been removed.

// playGeofenceAlert removed

// =========================================================================
// 7. RIWAYAT OPERASI LOGBOOK CONSOLIDATOR
// =========================================================================
// =========================================================================
// 7. RIWAYAT OPERASI LOGBOOK CONSOLIDATOR
// =========================================================================
let localHistoryList = [];
window.renderRiwayat = function () {
    const filterStart = document.getElementById('filter-tanggal-mulai') ? document.getElementById('filter-tanggal-mulai').value : '';
    const filterEnd = document.getElementById('filter-tanggal-selesai') ? document.getElementById('filter-tanggal-selesai').value : '';
    const query = document.getElementById('search-riwayat') ? document.getElementById('search-riwayat').value.toLowerCase().trim() : '';
    const tbody = document.getElementById('tbody-riwayat');
    if (!tbody) return;
    tbody.innerHTML = `<tr><td colspan="6" class="text-center text-muted py-4"><i class="fa-solid fa-circle-notch fa-spin me-2"></i> Mengompilasi data riwayat...</td></tr>`;

    get(refUsers).then((snapshot) => {
        const users = snapshot.val();
        tbody.innerHTML = '';
        if (!users) {
            tbody.innerHTML = `<tr><td colspan="6" class="text-center text-muted py-4">Tidak ada data pengguna.</td></tr>`;
            return;
        }

        let allHistory = [];

        for (let uid in users) {
            let u = users[uid];
            if (u.history) {
                for (let histKey in u.history) {
                    let h = u.history[histKey];
                    allHistory.push({
                        userNrp: u.nrp || '',
                        userNama: `${u.pangkat || ''} ${u.nama || ''}`.trim() || 'Anggota',
                        opCode: h.opCode || 'OPS-SIAGA-001',
                        jenisGiat: h.activityType || h.jenisGiat || 'Pengamanan Wilayah',
                        waktuMulai: h.startTime || h.waktuMulai || '',
                        waktuSelesai: h.endTime || h.waktuSelesai || '',
                        durasiDetik: h.durationSeconds !== undefined ? h.durationSeconds : (h.durasiDetik || 0),
                        jarakMeter: h.distance !== undefined ? h.distance : (h.jarakMeter || 0),
                        commander: h.commander || 'Mandiri',
                        personnelCount: h.personnelCount || 1,
                    });
                }
            }
        }

        // Urutkan berdasarkan waktu mulai terbaru
        allHistory.sort((a, b) => new Date(b.waktuMulai) - new Date(a.waktuMulai));

        // Filter rentang tanggal
        if (filterStart) {
            allHistory = allHistory.filter(h => h.waktuMulai && h.waktuMulai.split('T')[0] >= filterStart);
        }
        if (filterEnd) {
            allHistory = allHistory.filter(h => h.waktuMulai && h.waktuMulai.split('T')[0] <= filterEnd);
        }

        // Filter kueri pencarian teks
        if (query) {
            allHistory = allHistory.filter(h =>
                h.opCode.toLowerCase().includes(query) ||
                h.userNrp.toLowerCase().includes(query) ||
                h.userNama.toLowerCase().includes(query) ||
                h.jenisGiat.toLowerCase().includes(query)
            );
        }

        localHistoryList = allHistory; // Simpan untuk unduhCSV terfilter

        const page = currentPages.riwayat || 1;
        const limit = limitPages.riwayat;
        const startIdx = (page - 1) * limit;
        const endIdx = startIdx + limit;
        const pagedHistory = allHistory.slice(startIdx, endIdx);

        let totalJarakKm = 0;
        let totalDurasiDetik = 0;
        const totalMisi = allHistory.length;

        allHistory.forEach(h => {
            totalJarakKm += parseFloat((h.jarakMeter / 1000).toFixed(2));
            totalDurasiDetik += h.durasiDetik || 0;
        });

        const statJarak = document.getElementById('stat-jarak');
        if (statJarak) statJarak.innerHTML = `${totalJarakKm.toFixed(1)} <small class="fs-6">Km</small>`;

        const statDurasi = document.getElementById('stat-durasi-patroli');
        if (statDurasi) {
            const avgDurasiMin = totalMisi > 0 ? Math.round((totalDurasiDetik / totalMisi) / 60) : 0;
            statDurasi.innerHTML = `${avgDurasiMin} <small class="fs-6">Menit</small>`;
        }

        if (pagedHistory.length === 0) {
            tbody.innerHTML = `<tr><td colspan="6" class="text-center text-muted py-4">Tidak ada riwayat operasi ditemukan.</td></tr>`;
        } else {
            pagedHistory.forEach(h => {
                const durasiMin = Math.round(h.durasiDetik / 60);
                const jarakKm = (h.jarakMeter / 1000).toFixed(2);

                const formatWaktu = (dateStr) => {
                    if (!dateStr) return '-';
                    const d = new Date(dateStr);
                    if (isNaN(d.getTime())) return 'Invalid Date';
                    return d.toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' }) + ' WITA';
                };

                const formatTanggal = (dateStr) => {
                    if (!dateStr) return '-';
                    const d = new Date(dateStr);
                    if (isNaN(d.getTime())) return 'Invalid Date';
                    return d.toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric' });
                };

                tbody.innerHTML += `
                    <tr onclick="window.tampilkanRuteMisi('${h.userNrp}', '${h.userNama.replace(/'/g, "\\'")}', '${h.opCode}', ${h.durasiDetik}, ${h.jarakMeter}, '${h.waktuMulai}')" style="cursor: pointer;">
                        <td>
                            <div class="fw-bold">${formatTanggal(h.waktuMulai)}</div>
                            <div class="text-muted small">${formatWaktu(h.waktuMulai)} - ${h.waktuSelesai ? formatWaktu(h.waktuSelesai) : 'Selesai'}</div>
                        </td>
                        <td><span class="badge bg-primary bg-opacity-10 text-primary border border-primary font-monospace">${h.opCode}</span></td>
                        <td>
                            <div class="fw-bold">${h.userNama}</div>
                            <div class="text-muted small">NRP: ${h.userNrp}</div>
                        </td>
                        <td>${h.jenisGiat}</td>
                        <td><b>${h.commander || 'Mandiri'}</b></td>
                        <td>${h.personnelCount || 1} Orang</td>
                        <td>
                            <div><i class="fa-solid fa-clock text-muted me-1"></i> ${durasiMin} Menit</div>
                            <div class="text-muted small"><i class="fa-solid fa-road text-muted me-1"></i> ${jarakKm} Km</div>
                        </td>
                        <td><span class="badge bg-success bg-opacity-10 text-success border border-success badge-custom">Selesai</span></td>
                    </tr>
                `;
            });
        }

        window.setupPagination('tbody-riwayat', allHistory, page, limit, 'pagination-riwayat', window.renderRiwayat);
    }).catch(err => {
        tbody.innerHTML = `<tr><td colspan="6" class="text-center text-danger py-4">Gagal memuat logbook: ${err.message}</td></tr>`;
    });
};

window.bukaModalUnduhCSV = function () {
    const screenStart = document.getElementById('filter-tanggal-mulai') ? document.getElementById('filter-tanggal-mulai').value : '';
    const screenEnd = document.getElementById('filter-tanggal-selesai') ? document.getElementById('filter-tanggal-selesai').value : '';

    const radioAll = document.getElementById('csvRangeAll');
    const radioCustom = document.getElementById('csvRangeCustom');
    const modalStart = document.getElementById('csv-download-start');
    const modalEnd = document.getElementById('csv-download-end');
    const dateContainer = document.getElementById('csvModalDateContainer');

    if (screenStart || screenEnd) {
        if (radioCustom) radioCustom.checked = true;
        if (dateContainer) dateContainer.style.display = 'flex';
        if (modalStart) modalStart.value = screenStart;
        if (modalEnd) modalEnd.value = screenEnd;
    } else {
        if (radioAll) radioAll.checked = true;
        if (dateContainer) dateContainer.style.display = 'none';
        if (modalStart) modalStart.value = '';
        if (modalEnd) modalEnd.value = '';
    }

    const modalEl = document.getElementById('unduhCsvModal');
    const modal = bootstrap.Modal.getOrCreateInstance(modalEl);
    modal.show();
};

window.toggleCsvModalDateInputs = function () {
    const radioCustom = document.getElementById('csvRangeCustom');
    const dateContainer = document.getElementById('csvModalDateContainer');
    if (radioCustom && radioCustom.checked) {
        dateContainer.style.display = 'flex';
    } else if (dateContainer) {
        dateContainer.style.display = 'none';
    }
};

window.prosesUnduhCSV = function () {
    const isCustom = document.getElementById('csvRangeCustom').checked;
    const filterStart = isCustom ? document.getElementById('csv-download-start').value : '';
    const filterEnd = isCustom ? document.getElementById('csv-download-end').value : '';
    const followQuery = document.getElementById('csvFilterQuery').checked;
    const query = (followQuery && document.getElementById('search-riwayat')) ? document.getElementById('search-riwayat').value.toLowerCase().trim() : '';

    get(refUsers).then((snapshot) => {
        const users = snapshot.val();
        if (!users) return alert("Tidak ada data pengguna.", "Pemberitahuan", "warning");

        let allHistory = [];
        for (let uid in users) {
            let u = users[uid];
            if (u.history) {
                for (let histKey in u.history) {
                    let h = u.history[histKey];
                    allHistory.push({
                        userNrp: u.nrp || '',
                        userNama: `${u.pangkat || ''} ${u.nama || ''}`.trim() || 'Anggota',
                        opCode: h.opCode || 'OPS-SIAGA-001',
                        jenisGiat: h.activityType || h.jenisGiat || 'Pengamanan Wilayah',
                        waktuMulai: h.startTime || h.waktuMulai || '',
                        waktuSelesai: h.endTime || h.waktuSelesai || '',
                        durasiDetik: h.durationSeconds !== undefined ? h.durationSeconds : (h.durasiDetik || 0),
                        jarakMeter: h.distance !== undefined ? h.distance : (h.jarakMeter || 0),
                    });
                }
            }
        }

        // Sort
        allHistory.sort((a, b) => new Date(b.waktuMulai) - new Date(a.waktuMulai));

        // Filter date range
        if (filterStart) {
            allHistory = allHistory.filter(h => h.waktuMulai && h.waktuMulai.split('T')[0] >= filterStart);
        }
        if (filterEnd) {
            allHistory = allHistory.filter(h => h.waktuMulai && h.waktuMulai.split('T')[0] <= filterEnd);
        }

        // Filter query
        if (query) {
            allHistory = allHistory.filter(h =>
                h.opCode.toLowerCase().includes(query) ||
                h.userNrp.toLowerCase().includes(query) ||
                h.userNama.toLowerCase().includes(query) ||
                h.jenisGiat.toLowerCase().includes(query)
            );
        }

        if (allHistory.length === 0) {
            alert("Tidak ada data riwayat yang cocok dengan kriteria unduhan.", "Unduh Gagal", "warning");
            return;
        }

        let csvData = allHistory.map(h => ({
            Tanggal: new Date(h.waktuMulai).toLocaleDateString('id-ID'),
            WaktuMulai: new Date(h.waktuMulai).toLocaleTimeString('id-ID') + ' WITA',
            WaktuSelesai: h.waktuSelesai ? new Date(h.waktuSelesai).toLocaleTimeString('id-ID') + ' WITA' : 'Selesai',
            IDMisi: h.opCode,
            NRP: h.userNrp,
            Nama: h.userNama,
            Giat: h.jenisGiat,
            Komandan: h.commander || 'Mandiri',
            Kekuatan: (h.personnelCount || 1) + ' Orang',
            DurasiMenit: Math.round(h.durasiDetik / 60),
            JarakKm: (h.jarakMeter / 1000).toFixed(2),
        }));

        const headers = Object.keys(csvData[0]).join(",");
        const rows = csvData.map(row =>
            Object.values(row).map(val => `"${val}"`).join(",")
        );
        const csvContent = "data:text/csv;charset=utf-8," + [headers, ...rows].join("\n");

        const encodedUri = encodeURI(csvContent);
        const link = document.createElement("a");
        link.setAttribute("href", encodedUri);
        link.setAttribute("download", `riwayat_operasi_siaga_${new Date().toISOString().split('T')[0]}.csv`);
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);

        const modalEl = document.getElementById('unduhCsvModal');
        const modal = bootstrap.Modal.getInstance(modalEl);
        if (modal) modal.hide();
    }).catch(err => {
        alert("Gagal memuat data unduhan: " + err.message, "Error", "danger");
    });
};

// =========================================================================
// 8. SPA NAVIGASI PAGE VIEW
// =========================================================================
window.switchPage = function (pageId, element) {
    // Role-based route guard for Commander
    if (userRole === 'commander' && (pageId === 'manajemen' || pageId === 'geofence' || pageId === 'pengaturan')) {
        pageId = 'peta';
        element = document.getElementById('menu-peta');
    }

    document.querySelectorAll('.page-view').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));

    const activePage = document.getElementById('page-' + pageId);
    if (activePage) activePage.classList.add('active');
    if (element) element.classList.add('active');

    if (pageId === 'peta') setTimeout(() => { map.invalidateSize(); }, 200);
    if (pageId === 'geofence') setTimeout(() => { mapGeo.invalidateSize(); }, 200);
    if (pageId === 'riwayat') renderRiwayat();
    if (pageId === 'statistik') buildStatistik();
    if (pageId === 'chat') {
        if (typeof initChatListener === 'function') initChatListener();
        window.forceScrollToBottom(document.getElementById('chat-messages-area'));
        if (typeof _chatChannel !== 'undefined' && _chatChannel === 'umum') {
            _unreadPublicCount = 0;
            if (typeof updateGlobalChatBadges === 'function') updateGlobalChatBadges();
        }
    }

    // Auto hide/show floating chat bubble depending on current page to avoid double UI
    const floatBtn = document.getElementById('chat-float-btn');
    const floatPanel = document.getElementById('chat-float-panel');
    if (floatBtn) {
        if (pageId === 'chat') {
            floatBtn.style.display = 'none';
            if (floatPanel) floatPanel.style.display = 'none';
            _chatFloatOpen = false;
        } else if (window.authVerified) {
            floatBtn.style.display = 'flex';
        }
    }

    // Auto-collapse sidebar on mobile after navigating
    const sidebar = document.getElementById('sidebar');
    if (sidebar && window.innerWidth < 768) {
        sidebar.classList.add('collapsed');
    }
};



// =========================================================================
// 9. NEW COMMAND MODAL, MAP SEARCH, ROUTE MAP, & STATS CHARTS
// =========================================================================

// A. Command Modal Exporter
window.bukaModalKomando = function (nrp, nama) {
    const modalEl = document.getElementById('kirimKomandoModal');
    if (!modalEl) return;
    const komandoModal = new bootstrap.Modal(modalEl);
    komandoModal.show();

    document.getElementById('komandoTargetName').value = `${nama} (NRP: ${nrp})`;
    document.getElementById('komandoTargetNrp').value = nrp;
    document.getElementById('komandoText').value = '';

    setTimeout(() => {
        document.getElementById('komandoText').focus();
    }, 450);
};

// B. Submit command tactically
const btnKirimKomandoEl = document.getElementById('btnKirimKomandoInstan');
if (btnKirimKomandoEl) {
    btnKirimKomandoEl.addEventListener('click', () => {
        const nrp = document.getElementById('komandoTargetNrp').value;
        const pesan = document.getElementById('komandoText').value;
        if (!pesan.trim()) return alert("Perintah tidak boleh kosong!");

        push(refPesan, {
            target: "POL-" + nrp,
            pesan: pesan,
            waktu: new Date().toLocaleTimeString('id-ID') + " WITA",
            oleh: userPangkat + " " + userName
        }).then(() => {
            const modalEl = document.getElementById('kirimKomandoModal');
            const komandoModal = bootstrap.Modal.getInstance(modalEl);
            if (komandoModal) komandoModal.hide();
            alert(`Perintah taktis berhasil dikirim ke NRP ${nrp}!`);
        });
    });
}

// C. Map member search bar logic
const memberSearchInput = document.getElementById('map-member-search');
const memberSearchResults = document.getElementById('map-search-results');
if (memberSearchInput && memberSearchResults) {
    memberSearchInput.addEventListener('input', function () {
        const query = this.value.toLowerCase().trim();
        memberSearchResults.innerHTML = '';

        if (!query) {
            memberSearchResults.style.display = 'none';
            return;
        }

        let matches = [];
        for (let key in lastTrackingData) {
            const u = lastTrackingData[key];
            const text = `${u.nama} ${u.nrp} ${u.satker}`.toLowerCase();
            if (text.includes(query)) {
                matches.push(u);
            }
        }

        if (matches.length === 0) {
            memberSearchResults.innerHTML = '<div class="search-result-item text-muted text-center py-2">Tidak ada anggota aktif cocok</div>';
        } else {
            matches.forEach(u => {
                const div = document.createElement('div');
                div.className = 'search-result-item';
                div.innerHTML = `
                    <div class="fw-bold">${u.pangkat || ''} ${u.nama}</div>
                    <div class="text-muted" style="font-size: 10px;">NRP: ${u.nrp} | ${u.satker} | ${u.jenis_giat || 'Dinas'}</div>
                `;
                div.onclick = function () {
                    if (u.koordinat && u.koordinat.lat && u.koordinat.lng) {
                        map.setView([u.koordinat.lat, u.koordinat.lng], 15);
                        L.popup()
                            .setLatLng([u.koordinat.lat, u.koordinat.lng])
                            .setContent(`
                                <div style="font-family: 'Inter', sans-serif; padding: 5px; min-width: 200px;">
                                    <h6 class="fw-bold mb-0" style="color: var(--text-main); font-size: 13px;">${u.pangkat || ''} ${u.nama}</h6>
                                    <p class="mb-2 text-muted" style="font-size: 10px;">NRP: ${u.nrp} | ${u.satker}</p>
                                    <hr style="margin: 6px 0; border-color: var(--border-color);">
                                    <div class="d-flex justify-content-between mb-1" style="font-size: 11px;"><span>Aktivitas:</span> <b class="text-primary">${u.jenis_giat || 'Dinas'}</b></div>
                                    <div class="d-flex justify-content-between mb-1" style="font-size: 11px;"><span>Kendaraan:</span> <b>${u.vehicle || '-'}</b></div>
                                    <div class="d-flex justify-content-between" style="font-size: 11px;"><span>Update:</span> <b class="text-success">${new Date(u.waktu).toLocaleTimeString('id-ID')} WITA</b></div>
                                </div>
                            `)
                            .openOn(map);
                    }
                    memberSearchInput.value = '';
                    memberSearchResults.style.display = 'none';
                };
                memberSearchResults.appendChild(div);
            });
        }
        memberSearchResults.style.display = 'block';
    });

    document.addEventListener('click', function (e) {
        if (!memberSearchInput.contains(e.target) && !memberSearchResults.contains(e.target)) {
            memberSearchResults.style.display = 'none';
        }
    });
}

// D. Route Visualizer - Menampilkan info misi tanpa data rute dummy
window.tampilkanRuteMisi = function (nrp, nama, opCode, durasiDetik, jarakMeter, waktuMulai) {
    const modalEl = document.getElementById('routeVisualModal');
    if (!modalEl) return;
    const routeModal = new bootstrap.Modal(modalEl);
    routeModal.show();

    document.getElementById('route-user-name').innerText = nama;
    document.getElementById('route-user-nrp').innerText = nrp;
    document.getElementById('route-distance').innerText = jarakMeter > 0 ? (jarakMeter / 1000).toFixed(2) + ' Km' : '-';
    document.getElementById('route-duration').innerText = durasiDetik > 0 ? Math.round(durasiDetik / 60) + ' Menit' : '-';

    if (!window.modalRouteMap) {
        window.modalRouteMap = L.map('map-route', { zoomControl: false }).setView([-3.4428, 114.8306], 14);
        L.control.zoom({ position: 'bottomright' }).addTo(window.modalRouteMap);
        L.tileLayer(currentTheme === 'dark' ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png' : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
            attribution: '&copy; CARTO'
        }).addTo(window.modalRouteMap);
    }

    setTimeout(() => {
        window.modalRouteMap.invalidateSize();

        if (!window.routeLayerGroup) {
            window.routeLayerGroup = L.layerGroup().addTo(window.modalRouteMap);
        }
        window.routeLayerGroup.clearLayers();

        // Tampilkan pesan: data GPS tracking tidak tersimpan sebagai rute
        const infoPopup = L.popup({ closeButton: false, autoClose: false, closeOnClick: false })
            .setLatLng([-3.4428, 114.8306])
            .setContent(`
                <div style="font-family:'Inter',sans-serif;padding:8px;text-align:center;min-width:200px">
                    <i class="fa-solid fa-location-crosshairs" style="color:#ef4444;font-size:24px;display:block;margin-bottom:8px"></i>
                    <b style="font-size:13px">Data Rute GPS</b>
                    <p style="font-size:11px;color:#6b7280;margin:6px 0 0">Rute perjalanan real-time hanya tersimpan selama sesi aktif di perangkat HP. Data statistik (jarak & durasi) tercatat di database.</p>
                </div>
            `)
            .addTo(window.modalRouteMap);

        window.modalRouteMap.setView([-3.4428, 114.8306], 13);
    }, 300);
};

// E. Chart.js initializers
window.myActivePersonnelChart = null;
window.myPersonnelStatusChart = null;

function initCharts(activeCount, standbyCount) {
    const ctxLine = document.getElementById('activePersonnelChart');
    const ctxDoughnut = document.getElementById('personnelStatusChart');
    if (!ctxLine || !ctxDoughnut) return;

    if (typeof Chart === 'undefined') {
        console.warn("Chart.js library is not loaded yet.");
        return;
    }

    if (window.myActivePersonnelChart) {
        window.myActivePersonnelChart.destroy();
    }
    if (window.myPersonnelStatusChart) {
        window.myPersonnelStatusChart.destroy();
    }

    const labels = [];
    const dataTrend = [];

    // Compile history from localUsers
    let allHistory = [];
    for (let uid in localUsers) {
        let u = localUsers[uid];
        if (u.history) {
            for (let histKey in u.history) {
                let h = u.history[histKey];
                allHistory.push({
                    userNrp: u.nrp || '',
                    waktuMulai: h.startTime || h.waktuMulai || '',
                });
            }
        }
    }

    for (let i = 6; i >= 0; i--) {
        const d = new Date();
        d.setDate(d.getDate() - i);
        const dateStr = d.toISOString().split('T')[0];
        labels.push(d.toLocaleDateString('id-ID', { weekday: 'short', day: 'numeric' }));

        let uniqueUsersOnDay = new Set();

        // Count active units tracking on day 0
        if (i === 0 && lastTrackingData) {
            for (let trackKey in lastTrackingData) {
                const trackNrp = lastTrackingData[trackKey].nrp;
                if (trackNrp) uniqueUsersOnDay.add(trackNrp);
            }
        }

        allHistory.forEach(h => {
            if (h.waktuMulai && h.waktuMulai.split('T')[0] === dateStr) {
                if (h.userNrp) uniqueUsersOnDay.add(h.userNrp);
            }
        });

        dataTrend.push(uniqueUsersOnDay.size);
    }

    window.myActivePersonnelChart = new Chart(ctxLine, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Personel Aktif',
                data: dataTrend,
                borderColor: '#ef4444',
                backgroundColor: 'rgba(239, 68, 68, 0.1)',
                fill: true,
                tension: 0.4,
                borderWidth: 2,
                pointBackgroundColor: '#ef4444',
                pointBorderColor: '#ffffff',
                pointHoverBackgroundColor: '#ffffff',
                pointHoverBorderColor: '#ef4444',
                pointRadius: 4,
                pointHoverRadius: 6
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false }
            },
            scales: {
                y: {
                    grid: { color: 'rgba(255, 255, 255, 0.05)' },
                    ticks: { color: '#a1a1aa', stepSize: 2 }
                },
                x: {
                    grid: { display: false },
                    ticks: { color: '#a1a1aa' }
                }
            }
        }
    });

    window.myPersonnelStatusChart = new Chart(ctxDoughnut, {
        type: 'doughnut',
        data: {
            labels: ['On Duty', 'Standby'],
            datasets: [{
                data: [activeCount, standbyCount],
                backgroundColor: ['#10b981', '#6b7280'],
                borderColor: currentTheme === 'dark' ? '#18181b' : '#ffffff',
                borderWidth: 2
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        color: '#a1a1aa',
                        padding: 16,
                        font: { family: 'Inter', size: 11 }
                    }
                }
            },
            cutout: '70%'
        }
    });
}

// F. Toggle Map Statistics overlay panel
window.toggleMapStats = function () {
    const wrapper = document.getElementById('map-stats-wrapper');
    const toggleBtn = document.getElementById('btnMapStatsToggle');
    if (wrapper && toggleBtn) {
        wrapper.classList.toggle('collapsed');
        if (wrapper.classList.contains('collapsed')) {
            toggleBtn.innerHTML = '<i class="fa-solid fa-chevron-down me-1"></i> TAMPILKAN INFO';
            toggleBtn.title = "Tampilkan Statistik";
        } else {
            toggleBtn.innerHTML = '<i class="fa-solid fa-chevron-up me-1"></i> SEMBUNYIKAN INFO';
            toggleBtn.title = "Sembunyikan Statistik";
        }
    }
};

// G. Show Profile Details Modal
window.tampilkanProfilSaya = function (e) {
    if (e) e.preventDefault();
    const modalEl = document.getElementById('profilSayaModal');
    if (!modalEl) return;

    document.getElementById('profilAvatar').src = `https://ui-avatars.com/api/?name=${encodeURIComponent(userName || "User")}&background=0d6efd&color=fff&size=100`;
    document.getElementById('profilNama').innerText = userName || "-";
    document.getElementById('profilNrp').innerText = userNrp || "-";
    document.getElementById('profilPangkat').innerText = userPangkat || "-";
    document.getElementById('profilSatker').innerText = userSatker || "-";

    let displayRole = 'Personel';
    if (userRole === 'commander') displayRole = 'Komandan Kesatuan';
    if (userRole === 'admin') displayRole = 'Administrator Utama';
    document.getElementById('profilRole').innerText = displayRole;

    const roleBadge = document.getElementById('profilRoleBadge');
    if (roleBadge) {
        roleBadge.innerText = (userRole || 'member').toUpperCase();
        if (userRole === 'admin') {
            roleBadge.className = 'badge bg-danger bg-opacity-20 text-danger border border-danger mb-4';
        } else if (userRole === 'commander') {
            roleBadge.className = 'badge bg-warning bg-opacity-20 text-warning border border-warning mb-4';
        } else {
            roleBadge.className = 'badge bg-success bg-opacity-20 text-success border border-success mb-4';
        }
    }

    const profilModal = new bootstrap.Modal(modalEl);
    profilModal.show();
};

// H. Real-time Firebase Connection Health Listener
const connectedRef = ref(db, ".info/connected");
onValue(connectedRef, (snap) => {
    const statKesehatan = document.getElementById('stat-kesehatan');
    const dbStatusText = document.getElementById('db-status-text');
    const dbStatusBadge = document.getElementById('db-status-badge');

    if (statKesehatan) {
        if (snap.val() === true) {
            statKesehatan.innerText = "100%";
            statKesehatan.className = "fw-bold text-success m-0";
        } else {
            statKesehatan.innerText = "OFFLINE";
            statKesehatan.className = "fw-bold text-danger m-0";
        }
    }

    if (dbStatusText && dbStatusBadge) {
        if (snap.val() === true) {
            dbStatusText.innerText = "SISTEM AKTIF";
            dbStatusBadge.classList.remove('offline');
        } else {
            dbStatusText.innerText = "SISTEM OFFLINE";
            dbStatusBadge.classList.add('offline');
        }
    }
});

// =========================================================================
// 9. SYSTEM SETTINGS MANAGEMENT & REALTIME SYNC
// =========================================================================
window.systemSettings = {
    gps_interval: 10,
    stale_timeout: 15,
    sos_sound: true,
    geofence_sound: true,
    maintenance_mode: false
};

const refSettings = ref(db, 'system_settings');
onValue(refSettings, (snapshot) => {
    if (snapshot.exists()) {
        const val = snapshot.val();
        window.systemSettings = {
            gps_interval: (val.gps_interval !== undefined && !isNaN(parseInt(val.gps_interval))) ? parseInt(val.gps_interval) : 10,
            stale_timeout: (val.stale_timeout !== undefined && !isNaN(parseInt(val.stale_timeout))) ? parseInt(val.stale_timeout) : 15,
            sos_sound: val.sos_sound !== false,
            geofence_sound: val.geofence_sound !== false,
            maintenance_mode: val.maintenance_mode === true
        };
    } else {
        set(refSettings, {
            gps_interval: 10,
            stale_timeout: 15,
            sos_sound: true,
            geofence_sound: true,
            maintenance_mode: false
        });
    }

    // Sync values to UI inputs if elements exist
    const setGps = document.getElementById('set-gps-interval');
    const setStale = document.getElementById('set-stale-timeout');
    const setMaint = document.getElementById('set-maintenance-mode');

    if (setGps) setGps.value = window.systemSettings.gps_interval;
    if (setStale) setStale.value = window.systemSettings.stale_timeout;
    if (setMaint) setMaint.checked = window.systemSettings.maintenance_mode;
});

// =========================================================================
// 10. DATABASE PURGE FUNCTION
// =========================================================================
window.bersihkanDatabaseLama = function () {
    if (!requireAdmin()) return;
    window.showCustomConfirm(
        "Bersihkan Data Lama",
        "Apakah Anda yakin ingin membersihkan seluruh data riwayat operasi dan pesan chat (umum & pribadi) yang berusia lebih dari 30 hari? Sebelum riwayat operasi dihapus permanen, file backup arsip (CSV) akan diunduh secara otomatis.",
        () => {
            Promise.all([
                get(refUsers),
                get(ref(db, 'chat/umum')),
                get(ref(db, 'chat/dm'))
            ]).then(([usersSnap, chatUmumSnap, chatDmSnap]) => {
                if (!usersSnap.exists()) {
                    window.alert("Tidak ada data pengguna ditemukan.", "Pemberitahuan", "warning");
                    return;
                }
                const users = usersSnap.val();
                const thirtyDaysAgo = new Date();
                thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

                let deleteCount = 0;
                const updates = {};
                let archiveHistory = [];

                // 1. Bersihkan Riwayat Operasi Anggota (>30 Hari)
                for (let uid in users) {
                    const u = users[uid];
                    if (u.history) {
                        for (let histKey in u.history) {
                            const h = u.history[histKey];
                            const dateStr = h.startTime || h.waktuMulai;
                            if (dateStr) {
                                const entryDate = new Date(dateStr);
                                if (entryDate < thirtyDaysAgo) {
                                    updates[`users/${uid}/history/${histKey}`] = null;
                                    deleteCount++;

                                    // Simpan ke array arsip untuk di-backup ke CSV
                                    archiveHistory.push({
                                        userNrp: u.nrp || '',
                                        userNama: `${u.pangkat || ''} ${u.nama || ''}`.trim() || 'Anggota',
                                        opCode: h.opCode || 'OPS-SIAGA-001',
                                        jenisGiat: h.activityType || h.jenisGiat || 'Pengamanan Wilayah',
                                        waktuMulai: dateStr,
                                        waktuSelesai: h.endTime || h.waktuSelesai || '',
                                        durasiDetik: h.durationSeconds !== undefined ? h.durationSeconds : (h.durasiDetik || 0),
                                        jarakMeter: h.distance !== undefined ? h.distance : (h.jarakMeter || 0),
                                    });
                                }
                            }
                        }
                    }
                }

                // 2. Bersihkan Chat Umum (>30 Hari)
                let chatUmumDeleteCount = 0;
                if (chatUmumSnap.exists()) {
                    const chatUmum = chatUmumSnap.val();
                    for (let msgId in chatUmum) {
                        const m = chatUmum[msgId];
                        const dateStr = m.waktu;
                        if (dateStr) {
                            const msgDate = new Date(dateStr);
                            if (msgDate < thirtyDaysAgo) {
                                updates[`chat/umum/${msgId}`] = null;
                                chatUmumDeleteCount++;
                            }
                        }
                    }
                }

                // 3. Bersihkan Chat Pribadi/DM (>30 Hari)
                let chatDmDeleteCount = 0;
                if (chatDmSnap.exists()) {
                    const chatDm = chatDmSnap.val();
                    for (let convId in chatDm) {
                        const conv = chatDm[convId];
                        if (conv.messages) {
                            for (let msgId in conv.messages) {
                                const m = conv.messages[msgId];
                                const dateStr = m.waktu;
                                if (dateStr) {
                                    const msgDate = new Date(dateStr);
                                    if (msgDate < thirtyDaysAgo) {
                                        updates[`chat/dm/${convId}/messages/${msgId}`] = null;
                                        chatDmDeleteCount++;
                                    }
                                }
                            }
                        }
                    }
                }

                const totalDeleteCount = deleteCount + chatUmumDeleteCount + chatDmDeleteCount;
                if (totalDeleteCount === 0) {
                    window.alert("Tidak ditemukan data riwayat tugas atau pesan chat yang berusia lebih dari 30 hari.", "Pembersihan Selesai", "info");
                    return;
                }

                // A. Ekspor & Unduh data arsip riwayat tugas sebagai file CSV (jika ada)
                if (deleteCount > 0) {
                    try {
                        let csvData = archiveHistory.map(h => ({
                            Tanggal: new Date(h.waktuMulai).toLocaleDateString('id-ID'),
                            WaktuMulai: new Date(h.waktuMulai).toLocaleTimeString('id-ID') + ' WITA',
                            WaktuSelesai: h.waktuSelesai ? new Date(h.waktuSelesai).toLocaleTimeString('id-ID') + ' WITA' : 'Selesai',
                            IDMisi: h.opCode,
                            NRP: h.userNrp,
                            Nama: h.userNama,
                            Giat: h.jenisGiat,
                            DurasiMenit: Math.round(h.durasiDetik / 60),
                            JarakKm: (h.jarakMeter / 1000).toFixed(2),
                        }));

                        const headers = Object.keys(csvData[0]).join(",");
                        const rows = csvData.map(row =>
                            Object.values(row).map(val => `"${val}"`).join(",")
                        );
                        const csvContent = "data:text/csv;charset=utf-8,\uFEFF" + [headers, ...rows].join("\n");
                        const encodedUri = encodeURI(csvContent);
                        const link = document.createElement("a");
                        link.setAttribute("href", encodedUri);
                        link.setAttribute("download", `arsip_riwayat_siaga_${new Date().toISOString().split('T')[0]}.csv`);
                        document.body.appendChild(link);
                        link.click();
                        document.body.removeChild(link);
                    } catch (csvErr) {
                        console.error("Gagal mendownload backup CSV:", csvErr);
                    }
                }

                // B. Lakukan penghapusan data di Firebase
                update(ref(db), updates).then(() => {
                    let msgSummary = `Pembersihan berhasil dilakukan. Data yang terhapus:\n`;
                    if (deleteCount > 0) msgSummary += `• ${deleteCount} riwayat tugas (backup CSV berhasil diunduh)\n`;
                    if (chatUmumDeleteCount > 0) msgSummary += `• ${chatUmumDeleteCount} pesan chat umum\n`;
                    if (chatDmDeleteCount > 0) msgSummary += `• ${chatDmDeleteCount} pesan chat pribadi/DM\n`;

                    window.alert(msgSummary, "Pembersihan Berhasil", "success");
                    if (typeof window.renderRiwayat === 'function') {
                        window.renderRiwayat();
                    }
                }).catch(err => {
                    window.alert("Gagal menghapus data lama: " + err.message, "Error", "danger");
                });
            }).catch(err => {
                window.alert("Gagal membaca data database: " + err.message, "Error", "danger");
            });
        },
        "danger"
    );
};

// =========================================================================
// 10. STATISTIK KINERJA & CETAK RIWAYAT
// =========================================================================
window.buildStatistik = function () {
    const statOps = document.getElementById('stat-total-operasi');
    const statAng = document.getElementById('stat-total-anggota');
    const statJam = document.getElementById('stat-total-jam');
    const statJar = document.getElementById('stat-total-jarak');
    const statZon = document.getElementById('stat-zona-aktif');

    get(refUsers).then((snapshot) => {
        const users = snapshot.val();
        if (!users) return;

        let activeCount = 0;
        let totalHistoryCount = 0;
        let totalJarakMeter = 0;
        let totalDurasiDetik = 0;

        let activeZonesCount = 0;
        for (let key in zones) {
            if (zones[key] && zones[key].aktif !== false) {
                activeZonesCount++;
            }
        }

        for (let uid in users) {
            let u = users[uid];
            if (u.status !== 'active') continue;
            activeCount++;

            if (u.history) {
                for (let histKey in u.history) {
                    let h = u.history[histKey];
                    totalHistoryCount++;
                    totalJarakMeter += h.distance !== undefined ? h.distance : (h.jarakMeter || 0);
                    totalDurasiDetik += h.durationSeconds !== undefined ? h.durationSeconds : (h.durasiDetik || 0);
                }
            }
        }

        if (statOps) statOps.innerText = totalHistoryCount;
        if (statAng) statAng.innerText = activeCount;
        if (statJam) statJam.innerText = (totalDurasiDetik / 3600).toFixed(1);
        if (statJar) statJar.innerHTML = `${(totalJarakMeter / 1000).toFixed(1)} <small class="fs-6">Km</small>`;
        if (statZon) statZon.innerText = activeZonesCount;
    }).catch(err => {
        console.error("Gagal menghitung statistik:", err);
    });
};

window.bukaModalCetakPDF = function () {
    const screenStart = document.getElementById('filter-tanggal-mulai') ? document.getElementById('filter-tanggal-mulai').value : '';
    const screenEnd = document.getElementById('filter-tanggal-selesai') ? document.getElementById('filter-tanggal-selesai').value : '';

    const radioAll = document.getElementById('pdfRangeAll');
    const radioCustom = document.getElementById('pdfRangeCustom');
    const modalStart = document.getElementById('pdf-download-start');
    const modalEnd = document.getElementById('pdf-download-end');
    const dateContainer = document.getElementById('pdfModalDateContainer');

    if (screenStart || screenEnd) {
        if (radioCustom) radioCustom.checked = true;
        if (dateContainer) dateContainer.style.display = 'flex';
        if (modalStart) modalStart.value = screenStart;
        if (modalEnd) modalEnd.value = screenEnd;
    } else {
        if (radioAll) radioAll.checked = true;
        if (dateContainer) dateContainer.style.display = 'none';
        if (modalStart) modalStart.value = '';
        if (modalEnd) modalEnd.value = '';
    }

    const modalEl = document.getElementById('unduhPdfModal');
    const modal = bootstrap.Modal.getOrCreateInstance(modalEl);
    modal.show();
};

window.togglePdfModalDateInputs = function () {
    const radioCustom = document.getElementById('pdfRangeCustom');
    const dateContainer = document.getElementById('pdfModalDateContainer');
    if (radioCustom && radioCustom.checked) {
        dateContainer.style.display = 'flex';
    } else if (dateContainer) {
        dateContainer.style.display = 'none';
    }
};

window.prosesCetakPDF = function () {
    const getBaseUrl = () => {
        let loc = window.location.href;
        loc = loc.split('?')[0].split('#')[0];
        if (loc.endsWith('.html') || loc.endsWith('.php')) {
            return loc.substring(0, loc.lastIndexOf('/'));
        }
        return loc.endsWith('/') ? loc.slice(0, -1) : loc;
    };
    const logoPoldaUrl = getBaseUrl() + '/assets/logo_polda.png';
    const logoTikUrl = getBaseUrl() + '/assets/logo-tik.png';

    const isCustom = document.getElementById('pdfRangeCustom').checked;
    const filterStart = isCustom ? document.getElementById('pdf-download-start').value : '';
    const filterEnd = isCustom ? document.getElementById('pdf-download-end').value : '';
    const followQuery = document.getElementById('pdfFilterQuery').checked;
    const query = (followQuery && document.getElementById('search-riwayat')) ? document.getElementById('search-riwayat').value.toLowerCase().trim() : '';

    get(refUsers).then((snapshot) => {
        const users = snapshot.val();
        if (!users) return alert("Tidak ada data pengguna.", "Pemberitahuan", "warning");

        let allHistory = [];
        for (let uid in users) {
            let u = users[uid];
            if (u.history) {
                for (let histKey in u.history) {
                    let h = u.history[histKey];
                    allHistory.push({
                        userNrp: u.nrp || '',
                        userNama: `${u.pangkat || ''} ${u.nama || ''}`.trim() || 'Anggota',
                        opCode: h.opCode || 'OPS-SIAGA-001',
                        jenisGiat: h.activityType || h.jenisGiat || 'Pengamanan Wilayah',
                        waktuMulai: h.startTime || h.waktuMulai || '',
                        waktuSelesai: h.endTime || h.waktuSelesai || '',
                        durasiDetik: h.durationSeconds !== undefined ? h.durationSeconds : (h.durasiDetik || 0),
                        jarakMeter: h.distance !== undefined ? h.distance : (h.jarakMeter || 0),
                        commander: h.commander || 'Mandiri',
                        personnelCount: h.personnelCount || 1
                    });
                }
            }
        }

        // Sort
        allHistory.sort((a, b) => new Date(b.waktuMulai) - new Date(a.waktuMulai));

        // Filter date range
        if (filterStart) {
            allHistory = allHistory.filter(h => h.waktuMulai && h.waktuMulai.split('T')[0] >= filterStart);
        }
        if (filterEnd) {
            allHistory = allHistory.filter(h => h.waktuMulai && h.waktuMulai.split('T')[0] <= filterEnd);
        }

        // Filter query
        if (query) {
            allHistory = allHistory.filter(h =>
                h.opCode.toLowerCase().includes(query) ||
                h.userNrp.toLowerCase().includes(query) ||
                h.userNama.toLowerCase().includes(query) ||
                h.jenisGiat.toLowerCase().includes(query)
            );
        }

        if (allHistory.length === 0) {
            alert("Tidak ada data riwayat untuk dicetak!");
            return;
        }

        let tableRowsHtml = '';
        
        const formatWaktu = (dateStr) => {
            if (!dateStr) return '-';
            const d = new Date(dateStr);
            if (isNaN(d.getTime())) return '-';
            return d.toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' }) + ' WITA';
        };

        const formatTanggal = (dateStr) => {
            if (!dateStr) return '-';
            const d = new Date(dateStr);
            if (isNaN(d.getTime())) return '-';
            return d.toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric' });
        };

        allHistory.forEach(h => {
            const durasiMin = Math.round(h.durasiDetik / 60);
            const jarakKm = (h.jarakMeter / 1000).toFixed(2);
            const waktuTampil = `${formatTanggal(h.waktuMulai)}<br><small style="color: #666;">${formatWaktu(h.waktuMulai)} - ${h.waktuSelesai ? formatWaktu(h.waktuSelesai) : 'Selesai'}</small>`;

            tableRowsHtml += `
                <tr>
                    <td>${waktuTampil}</td>
                    <td><span style="font-family: monospace; font-weight: bold;">${h.opCode}</span></td>
                    <td>
                        <b>${h.userNama}</b><br>
                        <small style="color: #666;">NRP: ${h.userNrp}</small>
                    </td>
                    <td>${h.jenisGiat}</td>
                    <td>${h.commander || 'Mandiri'}</td>
                    <td>${h.personnelCount || 1} Orang</td>
                    <td>${durasiMin} Menit / ${jarakKm} Km</td>
                </tr>`;
        });

        const curDate = new Date().toLocaleDateString('id-ID', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
        let rangeText = "Semua Periode";
        if (filterStart && filterEnd) {
            rangeText = `Periode: ${filterStart} s/d ${filterEnd}`;
        } else if (filterStart) {
            rangeText = `Periode Sejak: ${filterStart}`;
        } else if (filterEnd) {
            rangeText = `Periode Sampai: ${filterEnd}`;
        }

        const iframe = document.createElement('iframe');
        iframe.style.position = 'fixed';
        iframe.style.right = '0';
        iframe.style.bottom = '0';
        iframe.style.width = '0';
        iframe.style.height = '0';
        iframe.style.border = '0';
        document.body.appendChild(iframe);

        const doc = iframe.contentWindow.document;
        doc.write(`
            <html>
            <head>
                <title>&nbsp;</title>
                <style>
                    @page {
                        size: A4;
                        margin: 2.5cm 2cm 2.5cm 2cm; /* Margin resmi di setiap lembar kertas (Atas, Kanan, Bawah, Kiri) */
                    }
                    body {
                        font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
                        color: #333;
                        margin: 0;
                        padding: 0;
                        line-height: 1.4;
                        background-color: #fff;
                    }
                    .header-container {
                        display: flex;
                        justify-content: space-between;
                        align-items: center;
                        border-bottom: 3px double #000;
                        padding-bottom: 15px;
                        margin-bottom: 30px;
                    }
                    .header-logo-left {
                        height: 75px;
                        width: auto;
                    }
                    .header-logo-right {
                        height: 65px;
                        width: auto;
                    }
                    .header-text {
                        text-align: center;
                        flex-grow: 1;
                        padding: 0 20px;
                    }
                    .header-text h2 { margin: 0; font-size: 16px; text-transform: uppercase; font-weight: bold; }
                    .header-text h3 { margin: 5px 0 0; font-size: 12px; text-transform: uppercase; font-weight: bold; }
                    .header-text p { margin: 5px 0 0; font-size: 9px; color: #333; font-weight: bold; line-height: 1.3; }
                    .report-title-section {
                        text-align: center;
                        margin-bottom: 25px;
                    }
                    .report-title-section h4 {
                        margin: 0;
                        font-size: 15px;
                        text-transform: uppercase;
                        text-decoration: underline;
                        font-weight: bold;
                    }
                    .report-title-section p {
                        margin: 5px 0 0;
                        font-size: 12px;
                        font-weight: bold;
                        color: #0d6efd;
                    }
                    .report-table {
                        width: 100%;
                        border-collapse: collapse;
                        margin-bottom: 30px;
                        font-size: 11px;
                    }
                    .report-table th {
                        background-color: #f3f4f6;
                        border: 1px solid #d1d5db;
                        padding: 10px 8px;
                        text-align: left;
                        font-weight: bold;
                        text-transform: uppercase;
                    }
                    .report-table td {
                        border: 1px solid #d1d5db;
                        padding: 10px 8px;
                        vertical-align: top;
                    }
                    .report-table tr:nth-child(even) {
                        background-color: #f9fafb;
                    }
                    .footer-section {
                        margin-top: 40px;
                        display: flex;
                        justify-content: flex-end;
                    }
                    .signature-box {
                        text-align: center;
                        width: 250px;
                        font-size: 11px;
                    }
                    .signature-box p {
                        margin: 0;
                    }
                    @media print {
                        body { padding: 0; }
                        .no-print { display: none; }
                    }
                </style>
            </head>
            <body>
                <div class="header-container">
                    <img class="header-logo-left" src="${logoPoldaUrl}" alt="Logo Polda" onerror="this.src='https://upload.wikimedia.org/wikipedia/commons/thumb/d/d4/Logo_Polri.png/200px-Logo_Polri.png'">
                    <div class="header-text">
                        <h2>KEPOLISIAN NEGARA REPUBLIK INDONESIA</h2>
                        <h3>DAERAH KALIMANTAN SELATAN</h3>
                        <p>Jalan Bina Praja Timur, Kelurahan Sungai Tiung, Kecamatan Cempaka, Kota Banjarbaru – Kalimantan Selatan – Indonesia</p>
                    </div>
                    <img class="header-logo-right" src="${logoTikUrl}" alt="Logo TIK" onerror="this.style.display='none'">
                </div>

                <div class="report-title-section">
                    <h4>LAPORAN RIWAYAT OPERASI PERSONEL SIAGA</h4>
                    <p>${rangeText}</p>
                </div>

                <table class="report-table">
                    <thead>
                        <tr>
                            <th>Waktu Tugas</th>
                            <th>ID Misi</th>
                            <th>Pelaksana (NRP)</th>
                            <th>Kegiatan (Giat)</th>
                            <th>Komandan</th>
                            <th>Kekuatan</th>
                            <th>Durasi / Jarak</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${tableRowsHtml}
                    </tbody>
                </table>

                <div class="footer-section">
                    <div class="signature-box">
                        <p>Banjarmasin, ${curDate}</p>
                        <p style="margin-bottom: 70px;">Administrator Utama SIAGA,</p>
                        <p><b>BID TIK POLDA KALSEL</b></p>
                    </div>
                </div>
            </body>
            </html>
        `);
        doc.close();

        // Tunggu sebentar agar resource logo selesai dimuat di iframe, lalu jalankan print
        setTimeout(() => {
            iframe.contentWindow.focus();
            iframe.contentWindow.print();
            setTimeout(() => {
                document.body.removeChild(iframe);
            }, 1000);
        }, 500);

        // Close modal
        const modalEl = document.getElementById('unduhPdfModal');
        const modal = bootstrap.Modal.getInstance(modalEl);
        if (modal) modal.hide();
    }).catch(err => {
        alert("Gagal memuat data cetak: " + err.message);
    });
};

// ============================================================
// LIVE CHAT — Firebase Realtime
// ============================================================
let _chatChannel = 'umum';       // 'umum' or 'dm'
let _chatPath = 'chat/umum';     // actual Firebase path for messages
let _currentDmConvId = null;     // conversation ID when in DM mode
let _currentDmTargetUid = null;  // UID of the person we're DM-ing
let _listener = null;
let _chatFloatListener = null;
let _chatFloatUnsubs = [];
let _chatFloatOpen = false;
let _unreadPublicCount = 0;
let _unreadDmCount = 0;
let _chatRefreshInterval = null;
let _chatUnsubs = []; // Track all chat listeners for cleanup
let _dmContactListeners = []; // DM sidebar listeners

window.switchChatChannel = function (channel, btn) {
    _chatChannel = channel;
    _chatPath = 'chat/umum';
    _currentDmConvId = null;
    _currentDmTargetUid = null;

    // Deselect DM contacts, select umum
    document.querySelectorAll('.chat-channel-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.dm-contact-btn').forEach(b => b.classList.remove('active'));
    if (btn) btn.classList.add('active');

    const el = document.getElementById('chat-channel-title');
    const sub = document.getElementById('chat-channel-subtitle');
    const icon = document.getElementById('chat-header-icon');
    const inp = document.getElementById('chat-input');
    if (el) el.textContent = 'Siaran Umum';
    if (sub) sub.textContent = 'Semua personel dapat melihat dan mengirim pesan';
    if (icon) { icon.className = 'fa-solid fa-hashtag'; icon.style.color = 'var(--text-muted)'; }
    if (inp) inp.placeholder = 'Kirim pesan ke #siaran-umum...';
    
    _unreadPublicCount = 0;
    updateGlobalChatBadges();

    initChatListener();
};

function initChatListener() {
    // Cleanup ALL previous listeners
    _chatUnsubs.forEach(unsub => { try { unsub(); } catch (e) { } });
    _chatUnsubs = [];
    if (_chatRefreshInterval) { clearInterval(_chatRefreshInterval); _chatRefreshInterval = null; }

    const area = document.getElementById('chat-messages-area');
    if (!area) { console.warn('[Chat] chat-messages-area not found in DOM'); return; }

    console.log(`[Chat] Starting listener on path: ${_chatPath}`);
    const chatRef = ref(db, _chatPath);

    // Store messages in memory for efficient rendering
    const messages = {};
    let initialLoaded = false;

    const doRender = () => {
        renderChatFromMemory(messages, area, 'chat-empty-state', false);
    };

    // Use onValue for fast initial bulk load of all messages
    const unsubValue = onValue(chatRef, (snap) => {
        if (!snap.exists()) {
            initialLoaded = true;
            doRender();
            return;
        }
        // Bulk load all messages at once
        const newMessages = {};
        snap.forEach(child => {
            newMessages[child.key] = { key: child.key, ...child.val() };
        });

        if (!initialLoaded) {
            // First load: replace all messages at once (fast)
            Object.assign(messages, newMessages);
            initialLoaded = true;
            console.log(`[Chat] Initial load: ${Object.keys(messages).length} messages`);
        } else {
            // Subsequent value events: sync changes
            // Add new / update changed
            for (const key in newMessages) {
                messages[key] = newMessages[key];
            }
            // Remove deleted
            for (const key in messages) {
                if (!newMessages[key]) delete messages[key];
            }
        }
        doRender();

        // Mark as read if we are in this DM conversation
        if (_currentDmConvId && auth.currentUser) {
            const lastReadKey = `dm_last_read_${_currentDmConvId}`;
            localStorage.setItem(lastReadKey, Date.now().toString());
            update(ref(db, `chat/dm/${_currentDmConvId}/last_read`), {
                [auth.currentUser.uid]: Date.now()
            }).catch(e => {});
        }
    }, err => console.error('[Chat] onValue error:', err));
    _chatUnsubs.push(unsubValue);
}

window.forceScrollToBottom = function(container) {
    if (!container) return;
    const scroll = () => { container.scrollTop = container.scrollHeight; };
    scroll();
    setTimeout(scroll, 50);
    setTimeout(scroll, 150);
    setTimeout(scroll, 300);
    setTimeout(scroll, 600);
};

// Render chat messages from in-memory object (used by onChildAdded approach)
function renderChatFromMemory(msgsObj, container, emptyId, isFloat) {
    const myUid = auth.currentUser ? auth.currentUser.uid : '';
    // Sort by Firebase key (push keys are chronologically ordered)
    // This is more reliable than sorting by waktu which may have timezone differences
    const msgs = Object.values(msgsObj).sort((a, b) => {
        return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
    });
    console.log(`[Chat] Rendering ${msgs.length} messages (myUid: ${myUid ? myUid.substring(0, 8) + '...' : 'none'})`);
    msgs.forEach((m, i) => {
        const isMine = m.uid === myUid;
        console.log(`  [${i}] ${isMine ? 'ME' : 'OTHER'} key=${m.key} waktu=${m.waktu || 'none'} pesan=${(m.pesan || '').substring(0, 20)}`);
    });

    const emptyEl = document.getElementById(emptyId);
    if (msgs.length === 0) {
        if (emptyEl) emptyEl.style.display = '';
        Array.from(container.children).forEach(c => {
            if (c.id !== emptyId) c.remove();
        });
        return;
    }
    if (emptyEl) emptyEl.style.display = 'none';

    // Clear and re-render
    Array.from(container.children).forEach(c => {
        if (c.id !== emptyId) c.remove();
    });

    msgs.forEach(msg => {
        const isMe = msg.uid === myUid;
        const inisial = (msg.nama || '?')[0].toUpperCase();
        const nama = `${msg.pangkat || ''} ${msg.nama || ''}`.trim() || 'Anggota';
        const waktu = msg.waktu ? new Date(msg.waktu).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' }) : '';

        const row = document.createElement('div');
        row.className = `chat-msg-row${isMe ? ' me' : ''}`;

        if (isMe) {
            // My messages: bubble on the right (no avatar)
            row.innerHTML = `
                <div class="msg-content">
                    <div class="d-flex align-items-center justify-content-end gap-2">
                        <button class="btn-delete-msg" onclick="window.hapusPesanChat('${msg.key}')" title="Hapus Pesan">
                            <i class="fa-solid fa-trash-can"></i>
                        </button>
                        <div class="chat-bubble me">${escapeHtml(msg.pesan || '')}</div>
                    </div>
                    <div class="chat-msg-meta" style="text-align:right;">${waktu}</div>
                </div>`;
        } else {
            // Others' messages: avatar + bubble on the left
            const showDelete = userRole === 'admin';
            row.innerHTML = `
                <div class="chat-avatar">${inisial}</div>
                <div class="msg-content">
                    <div class="chat-sender-name">${nama}</div>
                    <div class="d-flex align-items-center gap-2">
                        <div class="chat-bubble other">${escapeHtml(msg.pesan || '')}</div>
                        ${showDelete ? `
                        <button class="btn-delete-msg" onclick="window.hapusPesanChat('${msg.key}')" title="Hapus Pesan">
                            <i class="fa-solid fa-trash-can"></i>
                        </button>` : ''}
                    </div>
                    <div class="chat-msg-meta">${waktu}</div>
                </div>`;
        }
        container.appendChild(row);
    });

    window.forceScrollToBottom(container);
}

window.hapusPesanChat = function (messageKey) {
    window.showCustomConfirm("Hapus Pesan", "Apakah Anda yakin ingin menghapus pesan ini secara permanen?", async () => {
        const path = _chatPath + '/' + messageKey;
        try {
            await remove(ref(db, path));
            
            // Jika ini DM, perbarui metadata obrolan terakhir (lastMessage & updatedAt) agar konsisten di bilah samping
            if (_currentDmConvId) {
                const msgSnap = await get(ref(db, `chat/dm/${_currentDmConvId}/messages`));
                if (msgSnap.exists() && msgSnap.val() !== null) {
                    const messages = msgSnap.val();
                    const keys = Object.keys(messages).sort();
                    if (keys.length > 0) {
                        const lastMsgKey = keys[keys.length - 1];
                        const lastMsg = messages[lastMsgKey];
                        await update(ref(db, `chat/dm/${_currentDmConvId}`), {
                            lastMessage: (lastMsg.pesan || '').substring(0, 80),
                            updatedAt: lastMsg.waktu ? new Date(lastMsg.waktu).getTime() : Date.now(),
                            lastSender: lastMsg.uid || ''
                        });
                    } else {
                        await update(ref(db, `chat/dm/${_currentDmConvId}`), {
                            lastMessage: '-',
                            updatedAt: 0,
                            lastSender: ''
                        });
                    }
                } else {
                    await update(ref(db, `chat/dm/${_currentDmConvId}`), {
                        lastMessage: '-',
                        updatedAt: 0,
                        lastSender: ''
                    });
                }
            }
        } catch (err) {
            console.error('[Chat] Delete error:', err);
            alert('Gagal menghapus pesan: ' + err.message, 'Error', 'danger');
        }
    }, "danger");
};

function renderChatMessages(snap, container, emptyId, isFloat) {
    const myUid = auth.currentUser ? auth.currentUser.uid : '';
    const msgs = [];
    snap.forEach(child => msgs.push({ key: child.key, ...child.val() }));

    const emptyEl = document.getElementById(emptyId);
    if (msgs.length === 0) {
        if (emptyEl) emptyEl.style.display = '';
        // Bersihkan pesan lama
        Array.from(container.children).forEach(c => {
            if (c.id !== emptyId) c.remove();
        });
        return;
    }
    if (emptyEl) emptyEl.style.display = 'none';

    // Render ulang semua pesan
    Array.from(container.children).forEach(c => {
        if (c.id !== emptyId) c.remove();
    });

    msgs.forEach(msg => {
        const isMe = msg.uid === myUid;
        const inisial = (msg.nama || '?')[0].toUpperCase();
        const nama = `${msg.pangkat || ''} ${msg.nama || ''}`.trim() || 'Anggota';
        const waktu = msg.waktu ? new Date(msg.waktu).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' }) : '';

        if (isFloat) {
            // Format ringkas untuk floating panel
            const row = document.createElement('div');
            row.className = `chat-msg-row${isMe ? ' me' : ''}`;
            row.innerHTML = !isMe ? `
                <div class="chat-avatar">${inisial}</div>
                <div>
                    <div class="chat-sender-name" style="color:#6b7280;">${nama}</div>
                    <div class="chat-bubble other">${escapeHtml(msg.pesan || '')}</div>
                    <div class="chat-msg-meta">${waktu}</div>
                </div>` : `
                <div>
                    <div class="chat-bubble me">${escapeHtml(msg.pesan || '')}</div>
                    <div class="chat-msg-meta" style="text-align:right;">${waktu}</div>
                </div>`;
            container.appendChild(row);
        } else {
            // Format lengkap untuk halaman chat
            const row = document.createElement('div');
            row.className = `chat-msg-row${isMe ? ' me' : ''}`;
            row.innerHTML = !isMe ? `
                <div class="chat-avatar">${inisial}</div>
                <div style="max-width:70%">
                    <div class="chat-sender-name">${nama}</div>
                    <div class="chat-bubble other">${escapeHtml(msg.pesan || '')}</div>
                    <div class="chat-msg-meta">${waktu}</div>
                </div>` : `
                <div style="max-width:70%">
                    <div class="chat-bubble me">${escapeHtml(msg.pesan || '')}</div>
                    <div class="chat-msg-meta" style="text-align:right;">${waktu}</div>
                </div>`;
            container.appendChild(row);
        }
    });

    // Auto scroll ke bawah
    window.forceScrollToBottom(container);
}

function escapeHtml(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/\n/g, '<br>');
}

window.kirimPesan = function () {
    if (!requireAuthVerified()) return;
    const inp = document.getElementById('chat-input');
    const teks = inp ? inp.value.trim() : '';
    if (!teks) return;
    inp.value = '';

    const msgData = {
        uid: auth.currentUser.uid,
        nrp: userNrp || '',
        nama: userName || 'Anggota',
        pangkat: userPangkat || '',
        pesan: teks,
        waktu: new Date().toISOString()
    };

    console.log(`[Chat] Sending message to path '${_chatPath}': ${teks.substring(0, 30)}...`);
    push(ref(db, _chatPath), msgData).then(() => {
        console.log('[Chat] Message sent successfully.');
        // If DM, update conversation metadata
        if (_currentDmConvId) {
            update(ref(db, `chat/dm/${_currentDmConvId}`), {
                lastMessage: teks.substring(0, 80),
                updatedAt: Date.now(),
                lastSender: auth.currentUser.uid
            });
        }
    }).catch(err => {
        console.error('[Chat] Send error:', err);
        alert('Gagal mengirim pesan: ' + (err.message || err), 'Error', 'danger');
    });
};

// ============================================================
// DM (PRIVATE CHAT) — Open conversation & contact list
// ============================================================

/**
 * Open a private chat with a specific user.
 * Admin/Commander can initiate; Members can only reply to existing conversations.
 */
window.openPrivateChat = async function (targetUid, targetName) {
    if (!requireAuthVerified()) return;
    const myUid = auth.currentUser.uid;

    // Deselect umum button and other contacts
    document.querySelectorAll('.chat-channel-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.dm-contact-btn').forEach(b => b.classList.remove('active'));
    const clickedBtn = document.querySelector(`.dm-contact-btn[data-uid="${targetUid}"]`);
    if (clickedBtn) clickedBtn.classList.add('active');

    // Check if conversation already exists
    let convId = null;
    try {
        const dmSnap = await get(ref(db, 'chat/dm'));
        if (dmSnap.exists()) {
            dmSnap.forEach(child => {
                const participants = child.val().participants || {};
                if (participants[myUid] === true && participants[targetUid] === true) {
                    convId = child.key;
                }
            });
        }
    } catch (e) {
        console.warn('[DM] Error checking existing conversations:', e);
    }

    // If no conversation exists, check permissions
    if (!convId) {
        if (userRole !== 'admin' && userRole !== 'commander') {
            alert('Anda belum dapat memulai percakapan ini. Hanya Komandan dan Admin yang dapat memulai pesan pribadi.', 'Akses Ditolak', 'warning');
            // Revert to umum
            window.switchChatChannel('umum', document.getElementById('ch-umum'));
            return;
        }
        // Create new conversation
        const newConvRef = push(ref(db, 'chat/dm'));
        convId = newConvRef.key;
        await set(newConvRef, {
            participants: { [myUid]: true, [targetUid]: true },
            lastMessage: '',
            updatedAt: Date.now()
        });
        console.log(`[DM] Created new conversation: ${convId}`);
    }

    // Set state
    _chatChannel = 'dm';
    _chatPath = `chat/dm/${convId}/messages`;
    _currentDmConvId = convId;
    _currentDmTargetUid = targetUid;

    // Update header
    const el = document.getElementById('chat-channel-title');
    const sub = document.getElementById('chat-channel-subtitle');
    const icon = document.getElementById('chat-header-icon');
    const inp = document.getElementById('chat-input');
    if (el) el.textContent = targetName;
    if (sub) sub.textContent = 'Pesan pribadi';
    if (icon) { icon.className = 'fa-solid fa-user'; icon.style.color = '#3b82f6'; }
    if (inp) inp.placeholder = `Kirim pesan ke ${targetName}...`;

    // Mark as read: save current timestamp to localStorage & Firebase
    const lastReadKey = `dm_last_read_${convId}`;
    localStorage.setItem(lastReadKey, Date.now().toString());
    if (auth.currentUser) {
        const now = Date.now();
        console.log(`[DM-Debug] openPrivateChat updating DB last_read for ${convId} to ${now}`);
        update(ref(db, `chat/dm/${convId}/last_read`), {
            [auth.currentUser.uid]: now
        }).catch(e => console.warn('[DM-Debug] Failed to save last_read status to DB:', e));
    }

    // Recalculate _unreadDmCount and global badges
    const badge = document.getElementById(`dm-badge-${targetUid}`);
    if (badge && badge.style.display !== 'none') {
        _unreadDmCount = Math.max(0, _unreadDmCount - 1);
        updateGlobalChatBadges();
    }

    initChatListener();
};

/**
 * Load contact list for DM sidebar.
 * Admin/Commander see all active users; Members see only admin/commander.
 */
function loadContactList() {
    // Cleanup previous listeners
    _dmContactListeners.forEach(unsub => { try { unsub(); } catch (e) { } });
    _dmContactListeners = [];

    const container = document.getElementById('dm-contacts-list');
    if (!container) { console.warn('[DM] dm-contacts-list container not found'); return; }

    const myUid = auth.currentUser ? auth.currentUser.uid : '';
    const usersRef = ref(db, 'users');

    console.log('[DM] Loading contact list, myUid:', myUid, 'role:', userRole);

    const unsub = onValue(usersRef, (snap) => {
        if (!snap.exists()) {
            console.log('[DM] Users node is empty');
            container.innerHTML = '<div style="text-align:center;color:var(--text-muted);font-size:12px;padding:20px;">Belum ada pengguna</div>';
            return;
        }
        const users = [];
        snap.forEach(child => {
            const u = child.val();
            if (child.key === myUid) return;
            if (u.status !== 'active') return;
            if (userRole === 'member' && u.role !== 'admin' && u.role !== 'commander') return;
            users.push({ uid: child.key, ...u });
        });

        console.log('[DM] Found', users.length, 'contacts (filtered from', snap.size, 'users)');

        users.sort((a, b) => (a.nama || '').localeCompare(b.nama || ''));

        container.innerHTML = '';
        if (users.length === 0) {
            container.innerHTML = '<div style="text-align:center;color:var(--text-muted);font-size:12px;padding:20px;">Belum ada kontak tersedia</div>';
            return;
        }
        users.forEach(u => {
            const fullName = `${u.pangkat || ''} ${u.nama || '?'}`.trim();
            const initial = (u.nama || '?')[0].toUpperCase();
            const btn = document.createElement('button');
            btn.className = 'dm-contact-btn';
            btn.dataset.uid = u.uid;
            btn.onclick = () => window.openPrivateChat(u.uid, fullName);
            btn.innerHTML = `
                <div style="display:flex; align-items:center; gap:10px; width:100%;">
                    <div style="width:36px;height:36px;border-radius:50%;background:linear-gradient(135deg,#1d4ed8,#3b82f6);display:flex;align-items:center;justify-content:center;color:#fff;font-weight:700;font-size:14px;flex-shrink:0;">${initial}</div>
                    <div style="flex:1;min-width:0;text-align:left;">
                        <div style="font-size:13px;font-weight:600;color:var(--text-main);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${fullName}</div>
                        <div style="font-size:11px;color:var(--text-muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" id="dm-preview-${u.uid}">-</div>
                    </div>
                    <span class="dm-badge" id="dm-badge-${u.uid}" style="display:none;background:#ef4444;color:#fff;font-size:10px;font-weight:700;border-radius:50%;min-width:18px;height:18px;align-items:center;justify-content:center;padding:0 4px;">0</span>
                </div>
            `;
            container.appendChild(btn);
        });

        listenDmPreviews(myUid, users);
    }, (err) => {
        console.error('[DM] Failed to load contacts:', err.message);
        container.innerHTML = '<div style="text-align:center;color:#ef4444;font-size:12px;padding:20px;">Gagal memuat kontak</div>';
    });
    _dmContactListeners.push(unsub);
}

function updateGlobalChatBadges() {
    const totalUnread = _unreadPublicCount + _unreadDmCount;
    const badgeText = totalUnread > 99 ? '99+' : totalUnread;
    
    // Floating chat badge on the map page should only count public messages, not DMs
    const badge = document.getElementById('chat-float-badge');
    if (badge) {
        if (_unreadPublicCount > 0) {
            badge.style.display = 'flex';
            badge.textContent = _unreadPublicCount > 99 ? '99+' : _unreadPublicCount;
        } else {
            badge.style.display = 'none';
        }
    }
    
    const badgeMain = document.getElementById('badge-chat');
    if (badgeMain) {
        if (totalUnread > 0) {
            badgeMain.style.display = 'inline-block';
            badgeMain.textContent = badgeText;
        } else {
            badgeMain.style.display = 'none';
        }
    }

    const badgeUmum = document.getElementById('badge-ch-umum');
    if (badgeUmum) {
        if (_unreadPublicCount > 0) {
            badgeUmum.style.display = 'inline-block';
            badgeUmum.textContent = _unreadPublicCount > 99 ? '99+' : _unreadPublicCount;
        } else {
            badgeUmum.style.display = 'none';
        }
    }
}

/**
 * Listen for lastMessage updates in DM conversations for preview.
 */
function listenDmPreviews(myUid, users) {
    const dmRef = ref(db, 'chat/dm');
    const unsub = onValue(dmRef, (snap) => {
        if (!snap.exists()) {
            _unreadDmCount = 0;
            updateGlobalChatBadges();
            return;
        }
        
        let localDmUnread = 0;
        
        snap.forEach(child => {
            const conv = child.val();
            const participants = conv.participants || {};
            if (!participants[myUid]) return;

            const otherUid = Object.keys(participants).find(uid => uid !== myUid);
            if (!otherUid) return;

            // Ambil lastMessage langsung dari database tanpa perlu memeriksa keberadaan conv.messages
            const lastMessage = conv.lastMessage || '';

            // Update preview text
            const previewEl = document.getElementById(`dm-preview-${otherUid}`);
            if (previewEl) {
                previewEl.textContent = lastMessage || '-';
            }

            // Unread logic: compare updatedAt with stored last-read timestamp (local & db)
            const lastReadKey = `dm_last_read_${child.key}`;
            let lastReadLocal = parseInt(localStorage.getItem(lastReadKey) || '0', 10);
            const lastReadDb = (conv.last_read && conv.last_read[myUid]) ? parseInt(conv.last_read[myUid], 10) : 0;
            let lastRead = Math.max(lastReadLocal, lastReadDb);

            const updatedAt = conv.updatedAt || 0;
            const lastSender = conv.lastSender || '';

            // Auto-read if currently viewing (only write if DB is outdated to prevent infinite recursion loop)
            if (_currentDmTargetUid === otherUid) {
                if (lastReadDb < updatedAt) {
                    const newRead = Math.max(Date.now(), updatedAt);
                    localStorage.setItem(lastReadKey, newRead.toString());
                    if (auth.currentUser) {
                        console.log(`[DM-Debug] Marking as read in DB for ${child.key}: ${newRead}`);
                        update(ref(db, `chat/dm/${child.key}/last_read`), {
                            [auth.currentUser.uid]: newRead
                        }).catch(e => console.warn('[DM-Debug] DB update failed:', e));
                    }
                    lastRead = newRead;
                } else {
                    lastRead = lastReadDb;
                }
            }

            const badgeEl = document.getElementById(`dm-badge-${otherUid}`);
            const hasMessage = lastMessage && lastMessage !== '-';
            const isFromOther = lastSender ? lastSender !== myUid : false;
            const isUnread = hasMessage && isFromOther && updatedAt > lastRead && _currentDmTargetUid !== otherUid;

            console.log(`[DM-Debug] Conv: ${child.key} | otherUid: ${otherUid} | hasMsg: ${hasMessage} | isFromOther: ${isFromOther} | updatedAt: ${updatedAt} | lastReadLocal: ${lastReadLocal} | lastReadDb: ${lastReadDb} | isUnread: ${isUnread}`);

            let unreadCount = 0;
            if (isUnread) {
                if (conv.messages) {
                    for (const msgKey in conv.messages) {
                        const msg = conv.messages[msgKey];
                        const msgTime = msg.waktu ? new Date(msg.waktu).getTime() : 0;
                        if (msg.uid !== myUid && msgTime > lastRead) {
                            unreadCount++;
                        }
                    }
                }
                if (unreadCount === 0) {
                    unreadCount = 1;
                }
            }

            if (unreadCount > 0) {
                localDmUnread += unreadCount;
            }

            if (badgeEl) {
                if (unreadCount > 0) {
                    badgeEl.style.display = 'flex';
                    badgeEl.textContent = unreadCount > 99 ? '99+' : unreadCount;
                    badgeEl.style.background = '#ef4444';
                    badgeEl.style.color = '#fff';
                    badgeEl.style.borderRadius = '50%';
                    badgeEl.style.minWidth = '18px';
                    badgeEl.style.height = '18px';
                    badgeEl.style.fontSize = '9px';
                    badgeEl.style.fontWeight = 'bold';
                    badgeEl.style.alignItems = 'center';
                    badgeEl.style.justifyContent = 'center';
                    badgeEl.style.padding = '0 4px';
                } else {
                    badgeEl.style.display = 'none';
                }
            }
        });

        _unreadDmCount = localDmUnread;
        updateGlobalChatBadges();
    });
    _dmContactListeners.push(unsub);
}

window.kirimPesanFloat = function () {
    if (!requireAuthVerified()) return;
    const inp = document.getElementById('chat-float-input');
    const teks = inp ? inp.value.trim() : '';
    if (!teks) return;
    inp.value = '';
    push(ref(db, 'chat/umum'), {
        uid: auth.currentUser.uid,
        nrp: userNrp || '',
        nama: userName || 'Anggota',
        pangkat: userPangkat || '',
        pesan: teks,
        waktu: new Date().toISOString()
    }).catch(err => {
        alert('Gagal mengirim pesan: ' + (err.message || err), 'Error', 'danger');
    });
};

window.toggleFloatingChat = function () {
    if (window.floatBtnDragged) {
        window.floatBtnDragged = false;
        return; // Jangan buka chat panel jika tombol baru saja digeser/drag
    }
    const panel = document.getElementById('chat-float-panel');
    if (!panel) return;
    _chatFloatOpen = !_chatFloatOpen;
    if (_chatFloatOpen) {
        panel.style.display = 'flex';
        _unreadPublicCount = 0;
        updateGlobalChatBadges();
        
        // Auto scroll to bottom when panel is shown
        const floatArea = document.getElementById('chat-float-messages');
        if (floatArea) {
            window.forceScrollToBottom(floatArea);
        }
    } else {
        panel.style.display = 'none';
    }
};

function makeElementDraggable(elmnt, handle, isButton = false) {
    let pos1 = 0, pos2 = 0, pos3 = 0, pos4 = 0;
    let startX = 0, startY = 0;
    let hasMoved = false;
    
    handle.onmousedown = dragMouseDown;
    handle.ontouchstart = dragTouchStart;

    function dragMouseDown(e) {
        e = e || window.event;
        if (!isButton && (e.target.closest('button') || e.target.closest('i'))) return;
        e.preventDefault();
        pos3 = e.clientX;
        pos4 = e.clientY;
        startX = e.clientX;
        startY = e.clientY;
        hasMoved = false;
        document.onmouseup = closeDragElement;
        document.onmousemove = elementDrag;
        handle.style.cursor = 'grabbing';
    }

    function elementDrag(e) {
        e = e || window.event;
        e.preventDefault();
        pos1 = pos3 - e.clientX;
        pos2 = pos4 - e.clientY;
        pos3 = e.clientX;
        pos4 = e.clientY;
        
        if (Math.abs(e.clientX - startX) > 5 || Math.abs(e.clientY - startY) > 5) {
            hasMoved = true;
            if (isButton) {
                window.floatBtnDragged = true;
            }
        }
        
        const rect = elmnt.getBoundingClientRect();
        elmnt.style.bottom = 'auto';
        elmnt.style.right = 'auto';
        elmnt.style.top = (rect.top - pos2) + "px";
        elmnt.style.left = (rect.left - pos1) + "px";
    }

    function closeDragElement() {
        document.onmouseup = null;
        document.onmousemove = null;
        handle.style.cursor = isButton ? 'pointer' : 'grab';
        
        if (isButton && hasMoved) {
            // Beri jeda kecil agar handler event click bawaan tidak men-trigger toggle
            setTimeout(() => {
                window.floatBtnDragged = false;
            }, 50);
        }
    }
    
    // Support sentuhan jari (mobile/tablet)
    function dragTouchStart(e) {
        if (!isButton && (e.target.closest('button') || e.target.closest('i'))) return;
        const touch = e.touches[0];
        pos3 = touch.clientX;
        pos4 = touch.clientY;
        startX = touch.clientX;
        startY = touch.clientY;
        hasMoved = false;
        document.ontouchend = closeTouchDragElement;
        document.ontouchmove = touchElementDrag;
    }
    
    function touchElementDrag(e) {
        const touch = e.touches[0];
        pos1 = pos3 - touch.clientX;
        pos2 = pos4 - touch.clientY;
        pos3 = touch.clientX;
        pos4 = touch.clientY;
        
        if (Math.abs(touch.clientX - startX) > 5 || Math.abs(touch.clientY - startY) > 5) {
            hasMoved = true;
            if (isButton) {
                window.floatBtnDragged = true;
            }
        }
        
        const rect = elmnt.getBoundingClientRect();
        elmnt.style.bottom = 'auto';
        elmnt.style.right = 'auto';
        elmnt.style.top = (rect.top - pos2) + "px";
        elmnt.style.left = (rect.left - pos1) + "px";
    }
    
    function closeTouchDragElement() {
        document.ontouchend = null;
        document.ontouchmove = null;
        if (isButton && hasMoved) {
            setTimeout(() => {
                window.floatBtnDragged = false;
            }, 50);
        }
    }
}

// Tampilkan floating button setelah login
function initChatUI() {
    const floatBtn = document.getElementById('chat-float-btn');
    const activePage = document.querySelector('.page-view.active');
    const isActivePageChat = activePage && activePage.id === 'page-chat';
    if (floatBtn) {
        if (isActivePageChat) {
            floatBtn.style.display = 'none';
        } else {
            floatBtn.style.display = 'flex';
        }
        // Buat tombol chat bulat melayang bisa digeser-geser oleh user
        makeElementDraggable(floatBtn, floatBtn, true);
    }

    // Inisialisasi fitur geser (draggable) untuk panel chat melayang
    const panel = document.getElementById('chat-float-panel');
    const header = document.getElementById('chat-float-header');
    if (panel && header) {
        makeElementDraggable(panel, header, false);
    }
    // Cleanup previous listeners
    _chatFloatUnsubs.forEach(unsub => { try { unsub(); } catch (e) { } });
    _chatFloatUnsubs = [];

    const floatArea = document.getElementById('chat-float-messages');
    if (!floatArea) { console.warn('[Chat-Float] chat-float-messages not found'); return; }

    // In-memory message store for floating chat
    const floatMessages = {};

    const doRenderFloat = () => {
        renderChatFromMemory(floatMessages, floatArea, 'chat-float-empty', true);
    };

    const floatRef = ref(db, 'chat/umum');
    let floatInitialLoaded = false;

    // Use onValue for bulk load + real-time updates
    const unsubValue = onValue(floatRef, (snap) => {
        if (!snap.exists()) {
            floatInitialLoaded = true;
            doRenderFloat();
            return;
        }

        const newMessages = {};
        snap.forEach(child => {
            newMessages[child.key] = { key: child.key, ...child.val() };
        });

        if (!floatInitialLoaded) {
            // Initial bulk load — don't count as unread
            Object.assign(floatMessages, newMessages);
            floatInitialLoaded = true;
            console.log(`[Chat-Float] Initial load: ${Object.keys(floatMessages).length} messages`);
        } else {
            // Check for new messages (not in current store) — count as unread
            let newPublicUnread = 0;
            for (const key in newMessages) {
                const activePage = document.querySelector('.page-view.active');
                const isViewingUmum = (activePage && activePage.id === 'page-chat' && _chatChannel === 'umum');
                
                if (!floatMessages[key] && !_chatFloatOpen && !isViewingUmum) {
                    newPublicUnread++;
                }
                floatMessages[key] = newMessages[key];
            }
            if (newPublicUnread > 0) {
                _unreadPublicCount += newPublicUnread;
                updateGlobalChatBadges();
            }
            // Remove deleted
            for (const key in floatMessages) {
                if (!newMessages[key]) delete floatMessages[key];
            }
        }
        doRenderFloat();
    }, err => console.error('[Chat-Float] onValue error:', err));
    _chatFloatUnsubs.push(unsubValue);
}

// ============================================================
// LIVE STREAMING — WebRTC Receiver
// ============================================================
window.focusStreamLocation = function (lat, lng, event) {
    if (event) {
        event.preventDefault();
        event.stopPropagation();
    }
    map.setView([lat, lng], 16);
    switchPage('peta', document.getElementById('menu-peta'));
};

function setMediaBitrates(sdp, bitrateKbps) {
    let lines = sdp.split('\r\n');
    if (lines.length === 1) {
        lines = sdp.split('\n');
    }
    let newLines = [];
    let isVideoSection = false;

    for (let i = 0; i < lines.length; i++) {
        let line = lines[i];
        newLines.push(line);

        if (line.indexOf('m=video') === 0) {
            isVideoSection = true;
        } else if (line.indexOf('m=') === 0) {
            isVideoSection = false;
        }

        if (isVideoSection && line.indexOf('m=video') === 0) {
            let nextLine = lines[i + 1] || '';
            if (nextLine.indexOf('b=AS:') !== 0) {
                newLines.push('b=AS:' + bitrateKbps);
                newLines.push('b=TIAS:' + (bitrateKbps * 1000));
            }
        }
    }
    return newLines.join('\r\n');
}

window.geocodedAddresses = {};
window.getReverseGeocode = function (lat, lng, callback) {
    const latFixed = lat.toFixed(4);
    const lngFixed = lng.toFixed(4);
    const cacheKey = `${latFixed},${lngFixed}`;

    const fetchPromise = new Promise((resolve) => {
        if (window.geocodedAddresses[cacheKey]) {
            resolve(window.geocodedAddresses[cacheKey]);
            return;
        }

        // Try BigDataCloud Client API first (Faster, no strict rate limits)
        const bdcUrl = `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${lat}&longitude=${lng}&localityLanguage=id`;
        fetch(bdcUrl)
        .then(res => res.json())
        .then(data => {
            if (data) {
                const locality = data.locality || '';
                const city = data.city || '';
                const province = data.principalSubdivision || '';

                let addr = '';
                if (locality) addr += locality;
                if (city) addr += (addr ? ', ' : '') + city;
                if (province) addr += (addr ? ', ' : '') + province;

                if (addr) {
                    window.geocodedAddresses[cacheKey] = addr;
                    resolve(addr);
                    return;
                }
            }
            throw new Error('BigDataCloud resolved no address');
        })
        .catch(bdcErr => {
            console.warn('[Geocode] BigDataCloud failed, falling back to Nominatim:', bdcErr);
            
            // Fallback to Nominatim
            const nominatimUrl = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=17`;
            fetch(nominatimUrl)
            .then(res => res.json())
            .then(data => {
                if (data && data.address) {
                    const road = data.address.road || '';
                    const suburb = data.address.suburb || data.address.village || data.address.neighbourhood || '';
                    const city = data.address.city || data.address.regency || data.address.county || '';

                    let addr = '';
                    if (road) addr += road;
                    if (suburb) addr += (addr ? ', ' : '') + suburb;
                    if (city) addr += (addr ? ', ' : '') + city;

                    if (!addr && data.display_name) {
                        addr = data.display_name.split(',').slice(0, 3).join(',');
                    }

                    if (addr) {
                        window.geocodedAddresses[cacheKey] = addr;
                        resolve(addr);
                        return;
                    }
                }
                resolve(`Lat: ${lat.toFixed(5)}, Lng: ${lng.toFixed(5)}`);
            })
            .catch(nomErr => {
                console.error('[Geocode] Both geocoders failed:', nomErr);
                resolve(`Lat: ${lat.toFixed(5)}, Lng: ${lng.toFixed(5)}`);
            });
        });
    });

    if (callback) {
        fetchPromise.then(callback);
    }
    return fetchPromise;
};

window.activeStreams = {};
let activePeerConnections = {};

function initLiveOpsListener() {
    const refStreams = ref(db, 'streams');
    onValue(refStreams, (snapshot) => {
        const data = snapshot.val() || {};
        window.activeStreams = {};

        // Bersihkan peer connection untuk siaran yang sudah tidak aktif
        for (let uid in activePeerConnections) {
            if (!data[uid] || !data[uid].info || !data[uid].info.active) {
                closePeerConnection(uid);
            }
        }

        let activeCount = 0;
        for (let uid in data) {
            const stream = data[uid];
            if (stream.info && stream.info.active) {
                window.activeStreams[uid] = stream.info;
                activeCount++;
                // Auto-connect jika belum terhubung dan ada offer tersedia
                if (!activePeerConnections[uid] && stream.sdp && stream.sdp.offer) {
                    const info = stream.info;
                    const fullName = ((info.pangkat || '').trim() + ' ' + (info.nama || 'Anggota')).trim();
                    startWebRTCReceiver(uid, fullName, false);
                }
            }
        }

        // Update badge LIVE di sidebar
        const badgeLive = document.getElementById('badge-live');
        if (badgeLive) {
            if (activeCount > 0) {
                badgeLive.style.display = 'inline-flex';
                badgeLive.textContent = activeCount;
            } else {
                badgeLive.style.display = 'none';
            }
        }

        const countEl = document.getElementById('live-ops-active-count');
        if (countEl) countEl.textContent = `${activeCount} SIARAN AKTIF`;

        // Render grid jika halaman Live Ops sedang aktif
        renderLiveGrid();

        // Redraw map markers immediately so they display the red pulse and TONTON LIVE button
        if (typeof window.redrawMapMarkers === 'function') {
            window.redrawMapMarkers();
        }
    });
}

window.focusedStreamUids = [];
window.maximizedStreamUid = null;
window.toggleFocusStream = function (uid) {
    if (!uid) return;
    if (!window.focusedStreamUids) window.focusedStreamUids = [];
    const idx = window.focusedStreamUids.indexOf(uid);
    if (idx > -1) {
        window.focusedStreamUids.splice(idx, 1);
        if (window.maximizedStreamUid === uid) {
            window.maximizedStreamUid = null;
        }
    } else {
        window.focusedStreamUids.push(uid);
    }
    renderLiveGrid();
};

window.toggleMaximizeStream = function (uid) {
    if (!uid) return;
    const card = document.getElementById(`stream-card-${uid}`);
    if (!card) return;

    if (window.maximizedStreamUid === uid) {
        if (document.fullscreenElement) {
            document.exitFullscreen().catch(() => {});
        }
        window.maximizedStreamUid = null;
    } else {
        window.maximizedStreamUid = uid;
        // Make sure it is also in focusedStreamUids so layout maps correctly
        if (!window.focusedStreamUids.includes(uid)) {
            window.focusedStreamUids.push(uid);
        }
        if (card.requestFullscreen) {
            card.requestFullscreen().catch(() => {});
        } else if (card.webkitRequestFullscreen) {
            card.webkitRequestFullscreen().catch(() => {});
        } else if (card.msRequestFullscreen) {
            card.msRequestFullscreen().catch(() => {});
        }
    }
    renderLiveGrid();
};

document.addEventListener('fullscreenchange', () => {
    if (!document.fullscreenElement) {
        if (window.maximizedStreamUid !== null) {
            window.maximizedStreamUid = null;
            renderLiveGrid();
        }
    }
});

window.fullVideoStreamUids = {};
window.toggleCardFullVideo = function (uid) {
    if (!uid) return;
    if (!window.fullVideoStreamUids) window.fullVideoStreamUids = {};
    window.fullVideoStreamUids[uid] = !window.fullVideoStreamUids[uid];
    renderLiveGrid();
};

window.rotateVideo = function (uid, event) {
    if (event) {
        event.stopPropagation();
        event.preventDefault();
    }
    const videoEl = document.getElementById(`video-${uid}`);
    if (!videoEl) return;

    let rotation = parseInt(videoEl.dataset.rotation || '0');
    rotation = (rotation + 90) % 360;
    videoEl.dataset.rotation = rotation;

    const isCover = videoEl.style.objectFit !== 'contain';
    if (rotation === 90 || rotation === 270) {
        videoEl.style.transform = `rotate(${rotation}deg) scale(${isCover ? 1.78 : 0.56})`;
    } else {
        videoEl.style.transform = `rotate(${rotation}deg) scale(1)`;
    }
    console.log(`[WebRTC] Video ${uid} rotated to ${rotation} degrees (Scale: ${rotation === 90 || rotation === 270 ? (isCover ? 1.78 : 0.56) : 1})`);
};

window.webRecorders = {};

window.toggleWebRecord = function (uid, fullName) {
    const conn = activePeerConnections[uid];
    if (!conn) {
        alert('Koneksi tidak ditemukan. Tonton siaran terlebih dahulu.', 'Peringatan', 'warning');
        return;
    }

    const recordBtn = document.getElementById(`record-btn-${uid}`);
    const recordLabel = document.getElementById(`record-label-${uid}`);
    const recordIcon = document.getElementById(`record-icon-${uid}`);

    // If already recording, stop it
    if (window.webRecorders[uid]) {
        try {
            window.webRecorders[uid].stop();
        } catch (e) {
            console.error('Error stopping web recorder:', e);
        }
        delete window.webRecorders[uid];
        
        if (recordBtn) {
            recordBtn.style.background = '#18181b';
            recordBtn.style.border = '1px solid #27272a';
        }
        if (recordLabel) recordLabel.textContent = 'Rekam';
        if (recordIcon) {
            recordIcon.style.color = '#ef4444';
            recordIcon.style.animation = 'none';
        }
        alert(`Perekaman untuk ${fullName} selesai & diunduh.`, 'Berhasil', 'success');
        return;
    }

    // Start recording
    const videoEl = document.getElementById(`video-${uid}`);
    if (!videoEl || !videoEl.srcObject) {
        alert('Video belum aktif. Tunggu hingga video muncul.', 'Peringatan', 'warning');
        return;
    }

    const stream = videoEl.srcObject;
    if (stream.getTracks().length === 0) {
        alert('Tidak ada track media aktif untuk direkam.', 'Peringatan', 'warning');
        return;
    }

    try {
        let chunks = [];
        let audioContext = null;
        let mixedAudioTrack = null;

        // Mix remote voice (member) and local voice (admin mic) if VC is active
        const remoteAudioTrack = stream.getAudioTracks()[0];
        const localAudioStream = window.localVCStream;
        const localAudioTrack = localAudioStream ? localAudioStream.getAudioTracks()[0] : null;

        if (remoteAudioTrack && localAudioTrack && conn.vcActive) {
            try {
                audioContext = new (window.AudioContext || window.webkitAudioContext)();
                const remoteSource = audioContext.createMediaStreamSource(new MediaStream([remoteAudioTrack]));
                const localSource = audioContext.createMediaStreamSource(new MediaStream([localAudioTrack]));
                const destination = audioContext.createMediaStreamDestination();
                
                remoteSource.connect(destination);
                localSource.connect(destination);
                
                mixedAudioTrack = destination.stream.getAudioTracks()[0];
                console.log('[WebRTC] Successfully mixed remote and local audio tracks for two-way recording.');
            } catch (mixErr) {
                console.warn('[WebRTC] Failed to mix audio tracks, falling back to remote audio only:', mixErr);
            }
        }

        // Construct MediaStream to record
        let tracksToRecord = [];
        const videoTrack = stream.getVideoTracks()[0];
        if (videoTrack) tracksToRecord.push(videoTrack);

        if (mixedAudioTrack) {
            tracksToRecord.push(mixedAudioTrack);
        } else if (remoteAudioTrack) {
            tracksToRecord.push(remoteAudioTrack);
        }

        const recordStream = new MediaStream(tracksToRecord);

        // Deteksi apakah video dari HP dalam mode portrait menggunakan ukuran aslinya di layar
        let finalStream = recordStream;
        const isPortrait = videoEl.videoHeight > videoEl.videoWidth;
        if (isPortrait) {
            // Rekam menggunakan canvas untuk 'membakar' (bake) orientasi portrait
            // Karena MediaRecorder mengabaikan metadata rotasi dari HP
            const canvas = document.createElement('canvas');
            canvas.width = videoEl.videoWidth;
            canvas.height = videoEl.videoHeight;
            const ctx2d = canvas.getContext('2d');
            
            const drawFrame = () => {
                if (!window.webRecorders[uid]) return; // Stop jika rekaman selesai
                if (videoEl.readyState >= 2) {
                    ctx2d.drawImage(videoEl, 0, 0, canvas.width, canvas.height);
                }
                requestAnimationFrame(drawFrame);
            };
            
            const canvasVideoTrack = canvas.captureStream(30).getVideoTracks()[0];
            const audioTracks = tracksToRecord.filter(t => t.kind === 'audio');
            finalStream = new MediaStream([canvasVideoTrack, ...audioTracks]);
            
            // Mulai loop draw setelah MediaRecorder siap nanti
            setTimeout(() => drawFrame(), 500); 
            console.log('[WebRTC] Portrait video detected, recording with canvas rotation');
        }

        const options = { mimeType: 'video/webm;codecs=vp8,opus' };
        
        let mediaRecorder;
        try {
            mediaRecorder = new MediaRecorder(finalStream, options);
        } catch (mimeErr) {
            console.warn('[WebRTC] fallback to default MediaRecorder mimeType');
            mediaRecorder = new MediaRecorder(finalStream);
        }

        mediaRecorder.ondataavailable = (event) => {
            if (event.data && event.data.size > 0) {
                chunks.push(event.data);
            }
        };

        mediaRecorder.onstop = () => {
            if (audioContext) {
                try {
                    audioContext.close();
                } catch (cErr) {}
            }
            const blob = new Blob(chunks, { type: 'video/webm' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.style.display = 'none';
            a.href = url;
            
            const safeName = fullName.replace(/[^a-zA-Z0-9]/g, '_');
            const timeStamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '_');
            a.download = `SIAGA_Rec_${safeName}_${timeStamp}.webm`;
            
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        };

        mediaRecorder.start(1000);
        window.webRecorders[uid] = mediaRecorder;

        if (recordBtn) {
            recordBtn.style.background = '#ef4444';
            recordBtn.style.border = '1px solid transparent';
        }
        if (recordLabel) recordLabel.textContent = 'Merekam...';
        if (recordIcon) {
            recordIcon.style.color = '#fff';
            recordIcon.style.animation = 'pulse 1s infinite';
        }
        alert(`Merekam siaran ${fullName} (Video + Suara)...`, 'Info', 'info');
    } catch (err) {
        console.error('Failed to start MediaRecorder on web:', err);
        alert(`Gagal merekam siaran: ${err.message || err}`, 'Gagal', 'danger');
    }
};

async function ensureLocalVCStream() {
    if (window.localVCStream) return window.localVCStream;
    try {
        window.localVCStream = await navigator.mediaDevices.getUserMedia({
            audio: {
                echoCancellation: true,
                noiseSuppression: true
            },
            video: {
                width: { ideal: 320 },
                height: { ideal: 240 },
                frameRate: { ideal: 15 }
            }
        });
        return window.localVCStream;
    } catch (e) {
        console.warn('Gagal mendapatkan local stream untuk VC:', e);
        return null;
    }
}

window.toggleVC = async function (uid) {
    const conn = activePeerConnections[uid];
    if (!conn) return;

    if (conn.vcActive) {
        console.log(`[WebRTC] Stopping two-way VC for ${uid}`);
        if (conn.videoSender) await conn.videoSender.replaceTrack(null);
        if (conn.audioSender) await conn.audioSender.replaceTrack(null);
        conn.vcActive = false;
        
        // Update Firebase status
        await set(ref(db, `streams/${uid}/info/vcActive`), false);
        await set(ref(db, `streams/${uid}/info/vcVideoActive`), false);

        const vcBtn = document.getElementById(`vc-btn-${uid}`);
        if (vcBtn) {
            vcBtn.style.background = '#10b981';
            vcBtn.innerHTML = '<i class="fa-solid fa-video"></i><span>Hubungi Unit</span>';
        }
        const preview = document.getElementById(`local-preview-${uid}`);
        if (preview) preview.style.display = 'none';

        // Check if any other peer connection has an active VC
        const anyActiveVC = Object.values(activePeerConnections).some(c => c.vcActive);
        if (!anyActiveVC && window.localVCStream) {
            window.localVCStream.getTracks().forEach(t => t.stop());
            window.localVCStream = null;
        }

        renderLiveGrid();
        
        alert('Panggilan dua arah dihentikan.', 'Video Call', 'info');
    } else {
        console.log(`[WebRTC] Starting two-way VC for ${uid}`);
        const stream = await ensureLocalVCStream();
        if (!stream) {
            alert('Gagal mengakses kamera/mikrofon. Pastikan izin diberikan.', 'Error', 'danger');
            return;
        }

        stream.getAudioTracks().forEach(t => t.enabled = true);
        stream.getVideoTracks().forEach(t => t.enabled = true);

        if (conn.videoSender) {
            const videoTrack = stream.getVideoTracks()[0];
            await conn.videoSender.replaceTrack(videoTrack);
        }
        if (conn.audioSender) {
            const audioTrack = stream.getAudioTracks()[0];
            await conn.audioSender.replaceTrack(audioTrack);
        }
        conn.vcActive = true;
        conn.micActive = true;
        conn.camActive = true;

        // Update Firebase status
        await set(ref(db, `streams/${uid}/info/vcActive`), true);
        await set(ref(db, `streams/${uid}/info/vcVideoActive`), true);

        const vcBtn = document.getElementById(`vc-btn-${uid}`);
        if (vcBtn) {
            vcBtn.style.background = '#ef4444';
            vcBtn.innerHTML = '<i class="fa-solid fa-phone-slash"></i><span>Tutup Panggilan</span>';
        }

        const preview = document.getElementById(`local-preview-${uid}`);
        const previewVideo = document.getElementById(`local-video-${uid}`);
        if (preview && previewVideo) {
            preview.style.display = 'block';
            previewVideo.srcObject = stream;
            previewVideo.play().catch(() => {});
        }

        renderLiveGrid();
        
        alert('Panggilan dua arah aktif! Personel lapangan dapat melihat/mendengar Anda.', 'Video Call', 'success');
    }
};

window.toggleVCMic = async function (uid) {
    const conn = activePeerConnections[uid];
    if (!conn || !window.localVCStream) return;
    const isCurrentlyActive = conn.micActive !== false;
    const trackToUse = isCurrentlyActive ? null : window.localVCStream.getAudioTracks()[0];
    try {
        if (conn.audioSender) {
            await conn.audioSender.replaceTrack(trackToUse);
            conn.micActive = !isCurrentlyActive;
            renderLiveGrid();
        }
    } catch (e) {
        console.error('Gagal toggle mic:', e);
    }
};

window.toggleVCCam = async function (uid) {
    const conn = activePeerConnections[uid];
    if (!conn || !window.localVCStream) return;
    const isCurrentlyActive = conn.camActive !== false;
    const trackToUse = isCurrentlyActive ? null : window.localVCStream.getVideoTracks()[0];
    try {
        if (conn.videoSender) {
            await conn.videoSender.replaceTrack(trackToUse);
            conn.camActive = !isCurrentlyActive;
            
            // Nonaktifkan track kamera lokal untuk mematikan sensor kamera & menghemat daya
            const videoTrack = window.localVCStream.getVideoTracks()[0];
            if (videoTrack) {
                videoTrack.enabled = conn.camActive;
            }

            // Update Firebase video status
            await set(ref(db, `streams/${uid}/info/vcVideoActive`), conn.camActive);
            
            renderLiveGrid();
        }
    } catch (e) {
        console.error('Gagal toggle kamera:', e);
    }
};

function bindCardControls(parentEl, uid, streamFullName) {
    const watchBtn = parentEl.querySelector('.stream-btn');
    if (watchBtn) {
        watchBtn.onclick = (e) => {
            e.stopPropagation();
            window.toggleWatchStream(uid, streamFullName);
        };
    }
    const recordBtn = parentEl.querySelector(`#record-btn-${uid}`);
    if (recordBtn) {
        recordBtn.onclick = (e) => {
            e.stopPropagation();
            window.toggleWebRecord(uid, streamFullName);
        };
    }
    const vcBtn = parentEl.querySelector(`#vc-btn-${uid}`);
    if (vcBtn) {
        vcBtn.onclick = (e) => {
            e.stopPropagation();
            window.toggleVC(uid);
        };
    }
    const micBtn = parentEl.querySelector(`#vc-mic-btn-${uid}`);
    if (micBtn) {
        micBtn.onclick = (e) => {
            e.stopPropagation();
            window.toggleVCMic(uid);
        };
    }
    const camBtn = parentEl.querySelector(`#vc-cam-btn-${uid}`);
    if (camBtn) {
        camBtn.onclick = (e) => {
            e.stopPropagation();
            window.toggleVCCam(uid);
        };
    }

    const videoEl = parentEl.querySelector(`#video-${uid}`);
    if (videoEl) {
        if (videoEl.style.objectFit === 'contain') {
            videoEl.style.cursor = 'zoom-out';
        } else {
            videoEl.style.cursor = 'zoom-in';
        }
        videoEl.ondblclick = (e) => {
            e.stopPropagation();
            let rotation = parseInt(videoEl.dataset.rotation || '0');
            if (videoEl.style.objectFit === 'contain') {
                videoEl.style.objectFit = 'cover';
                videoEl.style.cursor = 'zoom-in';
                if (rotation === 90 || rotation === 270) {
                    videoEl.style.transform = `rotate(${rotation}deg) scale(1.78)`;
                } else {
                    videoEl.style.transform = `rotate(${rotation}deg) scale(1)`;
                }
            } else {
                videoEl.style.objectFit = 'contain';
                videoEl.style.cursor = 'zoom-out';
                if (rotation === 90 || rotation === 270) {
                    videoEl.style.transform = `rotate(${rotation}deg) scale(0.56)`;
                } else {
                    videoEl.style.transform = `rotate(${rotation}deg) scale(1)`;
                }
            }
        };
    }
}

function renderLiveGrid() {
    const grid = document.getElementById('live-ops-grid');
    const emptyState = document.getElementById('live-ops-empty-state');
    if (!grid || !emptyState) return;

    const uids = Object.keys(window.activeStreams);
    if (uids.length === 0) {
        grid.style.display = 'none';
        emptyState.style.display = 'flex';
        grid.innerHTML = '';
        window.focusedStreamUids = [];
        return;
    }

    emptyState.style.display = 'none';
    grid.style.display = 'grid';

    window.focusedStreamUids = (window.focusedStreamUids || []).filter(uid => uids.includes(uid));

    const hasFocus = window.focusedStreamUids.length > 0;

    if (hasFocus) {
        grid.classList.add('has-focus');
    } else {
        grid.classList.remove('has-focus');
    }

    let focusedArea = document.getElementById('focused-streams-area');
    let otherStreamsRow = document.getElementById('other-streams-row');

    if (hasFocus) {
        if (!focusedArea) {
            focusedArea = document.createElement('div');
            focusedArea.id = 'focused-streams-area';
            focusedArea.className = 'focused-streams-area';
            grid.appendChild(focusedArea);
        }
        if (!otherStreamsRow) {
            otherStreamsRow = document.createElement('div');
            otherStreamsRow.id = 'other-streams-row';
            otherStreamsRow.className = 'other-streams-row';
            grid.appendChild(otherStreamsRow);
        }
    } else {
        if (focusedArea) {
            focusedArea.remove();
            focusedArea = null;
        }
        if (otherStreamsRow) {
            otherStreamsRow.remove();
            otherStreamsRow = null;
        }
    }

    grid.querySelectorAll('.stream-card').forEach(card => {
        const cardUid = card.dataset.uid;
        if (cardUid && !uids.includes(cardUid)) {
            card.remove();
        }
    });

    uids.forEach(uid => {
        const info = window.activeStreams[uid];
        const isWatching = activePeerConnections[uid] !== undefined;
        const isConnected = activePeerConnections[uid] && activePeerConnections[uid].connected;
        const audioUnmuted = activePeerConnections[uid] && activePeerConnections[uid].audioUnmuted;
        const streamFullName = ((info.pangkat || '').trim() + ' ' + (info.nama || 'Anggota')).trim();

        const isFocused = window.focusedStreamUids.includes(uid);
        const isFullVideo = window.fullVideoStreamUids && window.fullVideoStreamUids[uid];
        const targetParent = isFocused ? focusedArea : (hasFocus ? otherStreamsRow : grid);

        const statusLabel = isConnected ? 'Terhubung' : (isWatching ? 'Menghubungkan...' : 'Menunggu');
        const updateCardLocation = (cardEl) => {
            const locContainer = cardEl.querySelector('.stream-location-container');
            if (locContainer) {
                const trackingKey = 'POL-' + info.nrp;
                const processLocation = (data) => {
                    if (data && data.koordinat && data.koordinat.lat && data.koordinat.lng) {
                        locContainer.style.display = 'flex';
                        const linkEl = locContainer.querySelector('.stream-location');
                        const latFixed = data.koordinat.lat.toFixed(4);
                        const lngFixed = data.koordinat.lng.toFixed(4);
                        if (cardEl.dataset.lastLat === latFixed && cardEl.dataset.lastLng === lngFixed) {
                            return;
                        }
                        cardEl.dataset.lastLat = latFixed;
                        cardEl.dataset.lastLng = lngFixed;
                        window.getReverseGeocode(data.koordinat.lat, data.koordinat.lng).then(address => {
                            if (linkEl) linkEl.textContent = address;
                            info.lastSeenAddress = address;
                        });
                    } else {
                        locContainer.style.display = 'none';
                    }
                };
                const trackingData = (window.lastTrackingSnapshotData && window.lastTrackingSnapshotData[trackingKey])
                    ? window.lastTrackingSnapshotData[trackingKey]
                    : null;
                if (trackingData) {
                    processLocation(trackingData);
                } else {
                    const dbRef = ref(db, 'live_tracking/' + trackingKey);
                    get(dbRef).then((snapshot) => {
                        if (snapshot.exists()) {
                            processLocation(snapshot.val());
                        } else {
                            locContainer.style.display = 'none';
                        }
                    }).catch(() => {
                        locContainer.style.display = 'none';
                    });
                }
            }
        };

        const locationHtml = info.lastSeenAddress 
            ? `<div class="stream-location-container" style="display:flex; align-items:center; gap:4px; font-size:9px; color:var(--primary); margin-top:2px; min-width:0; width:100%;">
                 <i class="fa-solid fa-location-dot" style="flex-shrink:0;"></i>
                 <span class="stream-location" style="display:inline-block; max-width:100%; vertical-align:middle; ${isFocused ? '' : 'white-space:nowrap; overflow:hidden; text-overflow:ellipsis;'}" title="${info.lastSeenAddress}">${info.lastSeenAddress}</span>
               </div>`
            : `<div class="stream-location-container" style="display:none; align-items:center; gap:4px; font-size:9px; color:var(--primary); margin-top:2px; min-width:0; width:100%;">
                 <i class="fa-solid fa-location-dot" style="flex-shrink:0;"></i>
                 <span class="stream-location"></span>
               </div>`;

        let controlsHtml = '';
        if (!isWatching) {
            controlsHtml = `
                <div style="display:flex; width:100%;">
                    <button class="stream-btn" style="width:100%; padding:6px 12px; border:none; border-radius:4px; cursor:pointer; font-size:11px; font-weight:600; background:#3b82f6; color:#fff; display:flex; align-items:center; justify-content:center; gap:4px; height:28px;">
                        <i class="fa-solid fa-play"></i><span>Tonton</span>
                    </button>
                </div>
            `;
        } else {
            const vcActive = activePeerConnections[uid] && activePeerConnections[uid].vcActive;
            const micActive = activePeerConnections[uid] && activePeerConnections[uid].micActive !== false;
            const camActive = activePeerConnections[uid] && activePeerConnections[uid].camActive !== false;
            const isRecording = window.webRecorders && window.webRecorders[uid] !== undefined;
            const recordBg = isRecording ? '#ef4444' : '#18181b';
            const recordBorder = isRecording ? '1px solid transparent' : '1px solid #27272a';
            const recordIconColor = isRecording ? '#fff' : '#ef4444';
            const recordAnim = isRecording ? 'pulse 1s infinite' : 'none';
            const recordText = isRecording ? (isFocused ? 'Merekam...' : 'Merekam') : 'Rekam';

            if (userRole !== 'admin') {
                controlsHtml = `
                    <div style="display:flex; flex-direction:column; gap:6px; width:100%;">
                        <div style="display:flex; gap:4px; align-items:center; width:100%;">
                            <button class="stream-btn watching" style="flex:1; padding:4px 2px; border:none; border-radius:4px; cursor:pointer; font-size:9px; font-weight:600; background:#ef4444; color:#fff; display:flex; align-items:center; justify-content:center; gap:2px; height:24px;">
                                <i class="fa-solid fa-stop-circle" style="font-size:9px;"></i><span>Hentikan</span>
                            </button>
                            <button class="record-btn" id="record-btn-${uid}" style="flex:1; padding:4px 2px; display:flex; align-items:center; justify-content:center; gap:2px; height:24px; font-size:9px; font-weight:600; border:none; border-radius:4px; cursor:pointer; background:${recordBg}; border:${recordBorder}; color:#fff;">
                                <i class="fa-solid fa-circle" id="record-icon-${uid}" style="color:${recordIconColor}; font-size:7px; animation:${recordAnim};"></i>
                                <span id="record-label-${uid}">${recordText}</span>
                            </button>
                        </div>
                        <div style="width:100%; text-align:center; padding:4px 8px; border-radius:4px; font-size:9px; font-weight:600; background:var(--bg-main); border:1px solid var(--border-color); color:var(--text-muted); display:flex; align-items:center; justify-content:center; height:22px;">Mode Pantau</div>
                    </div>
                `;
            } else {
                if (isFocused) {
                    controlsHtml = `
                        <div style="display:flex; justify-content:center; align-items:center; gap:12px; width:100%; padding:6px 0;">
                            <!-- Tombol Hentikan -->
                            <button class="stream-btn watching" title="Hentikan Siaran" style="width:36px; height:36px; border:none; border-radius:50%; cursor:pointer; background:#ef4444; color:#fff; display:flex; align-items:center; justify-content:center; font-size:14px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.15)'" onmouseout="this.style.transform='scale(1)'">
                                <i class="fa-solid fa-stop"></i>
                            </button>
                            <!-- Tombol Rekam -->
                            <button class="record-btn" id="record-btn-${uid}" title="${isRecording ? 'Hentikan Rekam' : 'Rekam Siaran'}" style="width:36px; height:36px; display:flex; align-items:center; justify-content:center; border:none; border-radius:50%; cursor:pointer; background:${recordBg}; border:${recordBorder}; color:#fff; font-size:14px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.15)'" onmouseout="this.style.transform='scale(1)'">
                                <i class="fa-solid fa-circle" id="record-icon-${uid}" style="color:${recordIconColor}; font-size:10px; animation:${recordAnim};"></i>
                            </button>
                            <!-- Tombol Video Call -->
                            <button class="vc-btn" id="vc-btn-${uid}" title="${vcActive ? 'Tutup Video Call' : 'Hubungi Video Call'}" style="width:36px; height:36px; border:none; border-radius:50%; cursor:pointer; background:${vcActive ? '#ef4444' : '#10b981'}; color:#fff; display:flex; align-items:center; justify-content:center; font-size:14px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.15)'" onmouseout="this.style.transform='scale(1)'">
                                <i class="fa-solid ${vcActive ? 'fa-phone-slash' : 'fa-video'}"></i>
                            </button>
                            <!-- Tombol Mic (Hanya jika VC aktif) -->
                            ${vcActive ? `
                                <button id="vc-mic-btn-${uid}" title="${micActive ? 'Mute Mic' : 'Aktifkan Mic'}" style="width:36px; height:36px; border:none; border-radius:50%; cursor:pointer; background:${micActive ? '#10b981' : '#18181b'}; border:1px solid ${micActive ? '#10b981' : '#27272a'}; color:#fff; display:flex; align-items:center; justify-content:center; font-size:14px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.15)'" onmouseout="this.style.transform='scale(1)'">
                                    <i class="fa-solid ${micActive ? 'fa-microphone' : 'fa-microphone-slash'}"></i>
                                </button>
                                <button id="vc-cam-btn-${uid}" title="${camActive ? 'Matikan Kamera' : 'Aktifkan Kamera'}" style="width:36px; height:36px; border:none; border-radius:50%; cursor:pointer; background:${camActive ? '#3b82f6' : '#18181b'}; border:1px solid ${camActive ? '#3b82f6' : '#27272a'}; color:#fff; display:flex; align-items:center; justify-content:center; font-size:14px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.15)'" onmouseout="this.style.transform='scale(1)'">
                                    <i class="fa-solid ${camActive ? 'fa-video' : 'fa-video-slash'}"></i>
                                </button>
                            ` : ''}
                        </div>
                    `;
                } else {
                    controlsHtml = `
                        <div style="display:flex; justify-content:center; align-items:center; gap:6px; width:100%;">
                            <!-- Tombol Hentikan -->
                            <button class="stream-btn watching" title="Hentikan Siaran" style="width:22px; height:22px; border:none; border-radius:50%; cursor:pointer; background:#ef4444; color:#fff; display:flex; align-items:center; justify-content:center; font-size:9px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.1)'" onmouseout="this.style.transform='scale(1)'">
                                <i class="fa-solid fa-stop"></i>
                            </button>
                            <!-- Tombol Rekam -->
                            <button class="record-btn" id="record-btn-${uid}" title="${isRecording ? 'Hentikan Rekam' : 'Rekam Siaran'}" style="width:22px; height:22px; display:flex; align-items:center; justify-content:center; border:none; border-radius:50%; cursor:pointer; background:${recordBg}; border:${recordBorder}; color:#fff; font-size:9px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.1)'" onmouseout="this.style.transform='scale(1)'">
                                <i class="fa-solid fa-circle" id="record-icon-${uid}" style="color:${recordIconColor}; font-size:6px; animation:${recordAnim};"></i>
                            </button>
                            <!-- Tombol Video Call -->
                            <button class="vc-btn" id="vc-btn-${uid}" title="${vcActive ? 'Tutup Video Call' : 'Hubungi Video Call'}" style="width:22px; height:22px; border:none; border-radius:50%; cursor:pointer; background:${vcActive ? '#ef4444' : '#10b981'}; color:#fff; display:flex; align-items:center; justify-content:center; font-size:9px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.1)'" onmouseout="this.style.transform='scale(1)'">
                                <i class="fa-solid ${vcActive ? 'fa-phone-slash' : 'fa-video'}"></i>
                            </button>
                            <!-- Tombol Mic (Hanya jika VC aktif) -->
                            ${vcActive ? `
                                <button id="vc-mic-btn-${uid}" title="${micActive ? 'Mute Mic' : 'Aktifkan Mic'}" style="width:22px; height:22px; border:none; border-radius:50%; cursor:pointer; background:${micActive ? '#10b981' : '#18181b'}; border:1px solid ${micActive ? '#10b981' : '#27272a'}; color:#fff; display:flex; align-items:center; justify-content:center; font-size:9px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.1)'" onmouseout="this.style.transform='scale(1)'">
                                    <i class="fa-solid ${micActive ? 'fa-microphone' : 'fa-microphone-slash'}"></i>
                                </button>
                                <button id="vc-cam-btn-${uid}" title="${camActive ? 'Matikan Kamera' : 'Aktifkan Kamera'}" style="width:22px; height:22px; border:none; border-radius:50%; cursor:pointer; background:${camActive ? '#3b82f6' : '#18181b'}; border:1px solid ${camActive ? '#3b82f6' : '#27272a'}; color:#fff; display:flex; align-items:center; justify-content:center; font-size:9px; transition:transform 0.15s ease-in-out;" onmouseover="this.style.transform='scale(1.1)'" onmouseout="this.style.transform='scale(1)'">
                                    <i class="fa-solid ${camActive ? 'fa-video' : 'fa-video-slash'}"></i>
                                </button>
                            ` : ''}
                        </div>
                    `;
                }
            }
        }

        const existingCard = document.getElementById(`stream-card-${uid}`);
        if (existingCard) {
            existingCard.style.display = '';
            const conn = activePeerConnections[uid];
            
            if (isFocused) {
                existingCard.classList.add('focused');
            } else {
                existingCard.classList.remove('focused');
            }

            if (isFullVideo) {
                existingCard.classList.add('full-video-mode');
            } else {
                existingCard.classList.remove('full-video-mode');
            }

            if (isWatching) {
                existingCard.classList.add('watching');
            } else {
                existingCard.classList.remove('watching');
            }

            const focusIcon = document.getElementById(`focus-icon-${uid}`);
            if (focusIcon) {
                focusIcon.className = `fa-solid ${isFocused ? 'fa-compress' : 'fa-expand'}`;
            }

            const focusBtn = document.getElementById(`focus-btn-${uid}`);
            if (focusBtn) {
                focusBtn.title = isFocused ? 'Kecilkan' : 'Fokus/Perbesar';
            }

            const toggleInfoIcon = document.getElementById(`toggle-info-icon-${uid}`);
            if (toggleInfoIcon) {
                toggleInfoIcon.className = `fa-solid ${isFullVideo ? 'fa-eye-slash' : 'fa-eye'}`;
            }

            const overlay = document.getElementById(`status-overlay-${uid}`);
            if (overlay) overlay.style.display = isConnected ? 'none' : 'flex';

            const statusLabelEl = document.getElementById(`status-label-${uid}`);
            if (statusLabelEl) statusLabelEl.textContent = statusLabel;

            const muteIcon = document.getElementById(`mute-icon-${uid}`);
            if (muteIcon) muteIcon.className = `fa-solid ${audioUnmuted ? 'fa-volume-high' : 'fa-volume-xmark'}`;

            updateCardLocation(existingCard);

            const preview = existingCard.querySelector(`#local-preview-${uid}`);
            if (preview) {
                const vcActive = conn && conn.vcActive;
                const camActive = conn && conn.camActive !== false;
                preview.style.display = (vcActive && camActive) ? 'block' : 'none';
            }

            // Update padding, fonts, and address text truncation based on focus state in the overlay
            const infoEl = existingCard.querySelector('.stream-overlay-info');
            if (infoEl) {
                infoEl.style.padding = isFocused ? '10px' : '6px 8px';
                
                const titleEl = infoEl.querySelector('.stream-title');
                if (titleEl) {
                    titleEl.style.fontSize = isFocused ? '12px' : '10px';
                    titleEl.style.whiteSpace = isFocused ? 'normal' : 'nowrap';
                    titleEl.style.overflow = isFocused ? 'visible' : 'hidden';
                    titleEl.style.textOverflow = isFocused ? 'clip' : 'ellipsis';
                }
                
                const metaEl = infoEl.querySelector('.stream-meta');
                if (metaEl) {
                    metaEl.style.fontSize = isFocused ? '9px' : '8px';
                }
                
                const locEl = infoEl.querySelector('.stream-location');
                if (locEl) {
                    locEl.style.whiteSpace = isFocused ? 'normal' : 'nowrap';
                    locEl.style.overflow = isFocused ? 'visible' : 'hidden';
                    locEl.style.textOverflow = isFocused ? 'clip' : 'ellipsis';
                }
            }

            const controlsContainer = existingCard.querySelector('.stream-controls-container');
            if (controlsContainer) {
                controlsContainer.innerHTML = controlsHtml;
                bindCardControls(existingCard, uid, streamFullName);
            }

            if (isWatching && conn) {
                const videoEl = existingCard.querySelector(`#video-${uid}`);
                if (videoEl && conn.remoteStream && conn.remoteStream.getTracks().length > 0 && !videoEl.srcObject) {
                    videoEl.srcObject = conn.remoteStream;
                    videoEl.muted = !audioUnmuted;
                    videoEl.play().catch(() => {});
                }
            }

            if (existingCard.parentElement !== targetParent) {
                targetParent.appendChild(existingCard);
            }

            return;
        }

        const card = document.createElement('div');
        card.className = `stream-card ${isFocused ? 'focused' : ''} ${isFullVideo ? 'full-video-mode' : ''}`;
        if (isWatching) {
            card.className += ' watching';
        }
        card.id = `stream-card-${uid}`;
        card.dataset.uid = uid;

        card.innerHTML = `
            <div class="stream-video-container" style="position:relative; background:#000; overflow:hidden; border-radius:8px;">
                <div class="stream-badge" style="position:absolute; top:8px; left:8px; z-index:10; background:#ef4444; color:#fff; font-size:8px; font-weight:700; padding:2px 6px; border-radius:3px; display:flex; align-items:center; gap:3px;">
                    <span style="width:4px;height:4px;background:#fff;border-radius:50%;display:inline-block;"></span>LIVE
                </div>
                <button id="focus-btn-${uid}" title="${isFocused ? 'Kecilkan' : 'Fokus/Perbesar'}" style="position:absolute; top:8px; right:64px; z-index:10; background:rgba(0,0,0,0.6); border:1px solid rgba(255,255,255,0.2); color:#fff; width:24px; height:24px; border-radius:50%; cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:10px; transition:background 0.2s;">
                    <i class="fa-solid ${isFocused ? 'fa-compress' : 'fa-expand'}" id="focus-icon-${uid}"></i>
                </button>
                <button id="max-btn-${uid}" title="Layar Penuh" style="position:absolute; top:8px; right:92px; z-index:10; background:rgba(0,0,0,0.6); border:1px solid rgba(255,255,255,0.2); color:#fff; width:24px; height:24px; border-radius:50%; cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:10px; transition:background 0.2s;">
                    <i class="fa-solid fa-maximize" id="max-icon-${uid}"></i>
                </button>
                <button id="toggle-info-btn-${uid}" title="Sembunyikan/Tampilkan Info & Kontrol" style="position:absolute; top:8px; right:36px; z-index:10; background:rgba(0,0,0,0.6); border:1px solid rgba(255,255,255,0.2); color:#fff; width:24px; height:24px; border-radius:50%; cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:10px; transition:background 0.2s;">
                    <i class="fa-solid ${isFullVideo ? 'fa-eye-slash' : 'fa-eye'}" id="toggle-info-icon-${uid}"></i>
                </button>
                <button id="rotate-btn-${uid}" title="Putar Tampilan" style="position:absolute; top:8px; right:120px; z-index:10; background:rgba(0,0,0,0.6); border:1px solid rgba(255,255,255,0.2); color:#fff; width:24px; height:24px; border-radius:50%; cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:10px; transition:background 0.2s;">
                    <i class="fa-solid fa-rotate"></i>
                </button>
                <button id="mute-btn-${uid}" title="Buka/Tutup Suara" style="position:absolute; top:8px; right:8px; z-index:10; background:rgba(0,0,0,0.6); border:1px solid rgba(255,255,255,0.2); color:#fff; width:24px; height:24px; border-radius:50%; cursor:pointer; display:flex; align-items:center; justify-content:center; font-size:10px; transition:background 0.2s;">
                    <i class="fa-solid ${audioUnmuted ? 'fa-volume-high' : 'fa-volume-xmark'}" id="mute-icon-${uid}"></i>
                </button>
                <div id="status-overlay-${uid}" style="position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; background:rgba(0,0,0,0.75); z-index:5; gap:6px;">
                    <div style="width:24px; height:24px; border:2px solid #3b82f6; border-top-color:transparent; border-radius:50%; animation:spin 1s linear infinite;"></div>
                    <span id="status-label-${uid}" style="font-size:9px; color:#a1a1aa;">${statusLabel}</span>
                </div>
                <div id="local-preview-${uid}" style="display:none; position:absolute; bottom:8px; right:8px; width:60px; aspect-ratio:4/3; background:#000; border:1px solid rgba(255,255,255,0.4); border-radius:4px; overflow:hidden; z-index:12;">
                    <video id="local-video-${uid}" autoplay muted playsinline style="width:100%; height:100%; object-fit:cover;"></video>
                </div>
                <video id="video-${uid}" autoplay playsinline style="width:100%; height:100%; object-fit:cover; display:block; transition: transform 0.2s;"></video>
                
                <!-- Transparent Overlay (Name, Location, Controls) -->
                <div class="stream-overlay-info" style="position:absolute; bottom:0; inset-x:0; z-index:8; background:linear-gradient(transparent, rgba(0,0,0,0.85)); padding:${isFocused ? '10px' : '6px 8px'}; display:flex; flex-direction:column; gap:4px; pointer-events:none; transition:opacity 0.2s;">
                    <div style="display:flex; justify-content:between; align-items:start; gap:4px; min-width:0; width:100%;">
                        <div style="width:100%; min-width:0; overflow:hidden; text-shadow:0 1px 2px rgba(0,0,0,0.8);">
                            <h6 class="stream-title" style="margin:0; font-weight:700; color:#fff; font-size:${isFocused ? '12px' : '10px'}; ${isFocused ? '' : 'white-space:nowrap; overflow:hidden; text-overflow:ellipsis;'}" title="${streamFullName}">${streamFullName}</h6>
                            <div class="stream-meta" style="font-size:${isFocused ? '9px' : '8px'}; color:#d4d4d8; margin-top:1px;">NRP: ${info.nrp || '-'} • ${info.satker || 'Bid TIK'}</div>
                            ${locationHtml}
                        </div>
                    </div>
                    <div class="stream-controls-container" id="controls-container-${uid}" style="width:100%; pointer-events:auto; margin-top:2px;">
                        ${controlsHtml}
                    </div>
                </div>
            </div>
        `;
        targetParent.appendChild(card);
 
        const focusBtn = document.getElementById(`focus-btn-${uid}`);
        if (focusBtn) {
            focusBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                window.toggleFocusStream(uid);
            });
        }
        const maxBtn = document.getElementById(`max-btn-${uid}`);
        if (maxBtn) {
            maxBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                window.toggleMaximizeStream(uid);
            });
        }
        const toggleInfoBtn = document.getElementById(`toggle-info-btn-${uid}`);
        if (toggleInfoBtn) {
            toggleInfoBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                window.toggleCardFullVideo(uid);
            });
        }
        const rotateBtn = document.getElementById(`rotate-btn-${uid}`);
        if (rotateBtn) {
            rotateBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                window.rotateVideo(uid, e);
            });
        }
        const muteBtn = document.getElementById(`mute-btn-${uid}`);
        if (muteBtn) {
            muteBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                window.toggleStreamMute(uid);
            });
        }

        bindCardControls(card, uid, streamFullName);

        if (isWatching && activePeerConnections[uid]) {
            const conn = activePeerConnections[uid];
            const videoEl = document.getElementById(`video-${uid}`);
            if (videoEl && conn.remoteStream && conn.remoteStream.getTracks().length > 0) {
                videoEl.srcObject = conn.remoteStream;
                videoEl.muted = !audioUnmuted;
                videoEl.play().catch(() => { });
            }
            const preview = document.getElementById(`local-preview-${uid}`);
            const previewVideo = document.getElementById(`local-video-${uid}`);
            if (preview && previewVideo && conn.vcActive && conn.camActive !== false) {
                preview.style.display = 'block';
                if (window.localVCStream) {
                    previewVideo.srcObject = window.localVCStream;
                    previewVideo.play().catch(() => {});
                }
            } else if (preview) {
                preview.style.display = 'none';
            }

            const overlay = document.getElementById(`status-overlay-${uid}`);
            if (overlay) {
                overlay.style.display = isConnected ? 'none' : 'flex';
            }
        }

        // Jalankan geocode lokasi untuk card baru
        updateCardLocation(card);
    });

    if (hasFocus && otherStreamsRow) {
        grid.appendChild(otherStreamsRow);
    }
}

window.toggleWatchStream = function (uid, fullName) {
    if (activePeerConnections[uid]) {
        closePeerConnection(uid, true);
        renderLiveGrid();
    } else {
        startWebRTCReceiver(uid, fullName, false);
        renderLiveGrid();
    }
};

// ============================================================
// AUDIO NOISE REDUCTION via Web Audio API
// ============================================================
let _webrtcAudioCtx = null;
let _audioProcessingReady = false;

/**
 * Initialize AudioContext on user gesture (required by browsers).
 * Call this from click/tap handlers.
 */
function ensureAudioContextReady() {
    try {
        if (!_webrtcAudioCtx || _webrtcAudioCtx.state === 'closed') {
            _webrtcAudioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }
        if (_webrtcAudioCtx.state === 'suspended') {
            _webrtcAudioCtx.resume();
        }
        _audioProcessingReady = true;
        console.log('[Audio] AudioContext ready, state:', _webrtcAudioCtx.state);
    } catch (e) {
        console.warn('[Audio] AudioContext init failed:', e);
    }
}

/**
 * Process a raw audio track through Web Audio API filters.
 * Returns cleaned audio track, or raw track if processing not ready.
 */
function processAudioTrack(rawAudioTrack) {
    if (!_audioProcessingReady || !_webrtcAudioCtx || _webrtcAudioCtx.state !== 'running') {
        console.log('[Audio] Processing not ready, using raw audio');
        return rawAudioTrack;
    }
    try {
        const ctx = _webrtcAudioCtx;
        const source = ctx.createMediaStreamSource(new MediaStream([rawAudioTrack]));

        // High-pass filter: cuts low-frequency buzz/hum below 150Hz
        const highPass = ctx.createBiquadFilter();
        highPass.type = 'highpass';
        highPass.frequency.value = 150;
        highPass.Q.value = 0.7;

        // Dynamics compressor: reduces background noise, normalizes volume
        const compressor = ctx.createDynamicsCompressor();
        compressor.threshold.value = -45;
        compressor.knee.value = 20;
        compressor.ratio.value = 6;
        compressor.attack.value = 0.005;
        compressor.release.value = 0.1;

        // Gain node for output volume
        const gainNode = ctx.createGain();
        gainNode.gain.value = 1.3;

        const destination = ctx.createMediaStreamDestination();

        source.connect(highPass);
        highPass.connect(compressor);
        compressor.connect(gainNode);
        gainNode.connect(destination);

        console.log('[Audio] Noise reduction active: HP(150Hz) -> Compressor -> Gain');
        return destination.stream.getAudioTracks()[0];
    } catch (e) {
        console.warn('[Audio] Noise reduction failed, using raw audio:', e);
        return rawAudioTrack;
    }
}

window.toggleStreamMute = function (uid) {
    const videoEl = document.getElementById(`video-${uid}`);
    const iconEl = document.getElementById(`mute-icon-${uid}`);
    if (!videoEl) return;

    // Simple mute/unmute toggle on the raw stream
    videoEl.muted = !videoEl.muted;

    if (activePeerConnections[uid]) {
        activePeerConnections[uid].audioUnmuted = !videoEl.muted;
    }
    if (iconEl) {
        iconEl.className = videoEl.muted ? 'fa-solid fa-volume-xmark' : 'fa-solid fa-volume-high';
    }
    // Ensure playback continues
    if (videoEl.paused) {
        videoEl.play().catch(() => { });
    }
};

function createDynamicFloatingPanel(uid, fullName) {
    if (document.getElementById(`live-floating-panel-${uid}`)) return;

    // Calculate cascading position based on how many floating panels are currently active
    const existingPanels = document.querySelectorAll('.live-floating-panel');
    const offset = existingPanels.length * 30; // 30px offset per panel
    
    // Cascading within limits so they don't slide off screen entirely
    const bottom = 28 + (offset % 240);
    const right = 160 + (offset % 240);

    const panelHtml = `
        <div id="live-floating-panel-${uid}" class="live-floating-panel" style="position:fixed; bottom:${bottom}px; right:${right}px; z-index:3500; width:180px; background:#18181b; border:1px solid #27272a; border-radius:8px; box-shadow:0 20px 50px rgba(0,0,0,0.6); display:flex; flex-direction:column; overflow:hidden; animation:slideUpChat 0.25s ease;">
            <div id="live-float-header-${uid}" style="padding:6px 10px; background:#1c1c1f; border-bottom:1px solid #27272a; display:flex; align-items:center; gap:8px; cursor:move; user-select:none;">
                <span class="pulse-red" style="width:6px; height:6px; background:#ef4444; border-radius:50%;"></span>
                <span id="live-float-title-${uid}" style="font-size:10px; font-weight:700; color:#fff; flex:1; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">LIVE: ${fullName}</span>
                <button onclick="window.closeFloatingLiveStream('${uid}')" style="background:none;border:none;cursor:pointer;color:#6b7280;padding:2px;" title="Tutup">
                    <i class="fa-solid fa-xmark" style="font-size:12px;"></i>
                </button>
            </div>
            <div style="position:relative; width:100%; aspect-ratio:3/4; background:#000; display:flex; align-items:center; justify-content:center;">
                <video id="live-float-video-${uid}" autoplay playsinline style="width:100%; height:100%; object-fit:cover;"></video>
                <div id="live-float-loading-${uid}" style="position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; background:rgba(0,0,0,0.8); gap:10px; color:#fff;">
                    <div class="spinner-border spinner-border-sm text-primary" role="status"></div>
                    <span style="font-size:9px; color:#a1a1aa;">Menghubungkan WebRTC...</span>
                </div>
            </div>
        </div>
    `;

    // Append to live-floating-container (or body if container is not found)
    const container = document.getElementById('live-floating-container') || document.body;
    container.insertAdjacentHTML('beforeend', panelHtml);

    // Make the panel draggable using header
    const panelEl = document.getElementById(`live-floating-panel-${uid}`);
    const headerEl = document.getElementById(`live-float-header-${uid}`);
    if (panelEl && headerEl) {
        makeElementDraggable(panelEl, headerEl);
    }
}

window.watchLiveStream = function (uid, fullName) {
    // Show peta page
    switchPage('peta', document.getElementById('menu-peta'));

    // Create the dynamic floating panel if it doesn't exist yet
    createDynamicFloatingPanel(uid, fullName);

    // If there's already an active connection for this stream, reuse it (swap to floating)
    if (activePeerConnections[uid]) {
        console.log('[WebRTC] Reusing existing connection for floating panel');
        const conn = activePeerConnections[uid];
        conn.isFloating = true;

        const title = document.getElementById(`live-float-title-${uid}`);
        const loading = document.getElementById(`live-float-loading-${uid}`);
        if (title) title.textContent = `LIVE: ${fullName}`;

        // Attach stream to floating video
        const floatVideo = document.getElementById(`live-float-video-${uid}`);
        if (floatVideo && conn.remoteStream) {
            floatVideo.srcObject = conn.remoteStream;
            floatVideo.muted = false;
            floatVideo.play().catch(e => console.warn('[WebRTC] Float autoplay:', e));
            if (loading) loading.style.display = conn.connected ? 'none' : 'flex';
        } else if (loading) {
            loading.style.display = 'flex';
        }
        return;
    }

    // No existing connection, start a new one
    startWebRTCReceiver(uid, fullName, true);
};

window.closeFloatingLiveStream = function (uid) {
    if (uid) {
        // Remove specific panel
        const panel = document.getElementById(`live-floating-panel-${uid}`);
        if (panel) panel.remove();

        if (activePeerConnections[uid]) {
            activePeerConnections[uid].isFloating = false;
        }
        // When closing in Tactical Map, fully close the stream to save user bandwidth & battery
        closePeerConnection(uid);
    } else {
        // Close all floating panels
        const panels = document.querySelectorAll('.live-floating-panel');
        panels.forEach(p => p.remove());

        for (let id in activePeerConnections) {
            if (activePeerConnections[id].isFloating) {
                activePeerConnections[id].isFloating = false;
                closePeerConnection(id);
            }
        }
    }
    renderLiveGrid();
};

const iceConfiguration = {
    iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:stun1.l.google.com:19302' },
        { urls: 'stun:stun2.l.google.com:19302' },
        {
            urls: 'turn:global.relay.metered.ca:80',
            username: 'f70015eec8deaa9ac60b9e9d',
            credential: 'JUdl1rA+ZXvisE3P'
        },
        {
            urls: 'turn:global.relay.metered.ca:443',
            username: 'f70015eec8deaa9ac60b9e9d',
            credential: 'JUdl1rA+ZXvisE3P'
        },
        {
            urls: 'turn:global.relay.metered.ca:443?transport=tcp',
            username: 'f70015eec8deaa9ac60b9e9d',
            credential: 'JUdl1rA+ZXvisE3P'
        },
        {
            urls: 'turns:global.relay.metered.ca:443',
            username: 'f70015eec8deaa9ac60b9e9d',
            credential: 'JUdl1rA+ZXvisE3P'
        },
        {
            urls: 'turns:global.relay.metered.ca:443?transport=tcp',
            username: 'f70015eec8deaa9ac60b9e9d',
            credential: 'JUdl1rA+ZXvisE3P'
        },
        // IP Fallbacks (bila resolusi DNS global.relay.metered.ca diblokir/timeout di jaringan lokal)
        {
            urls: 'turn:172.236.136.45:80',
            username: 'f70015eec8deaa9ac60b9e9d',
            credential: 'JUdl1rA+ZXvisE3P'
        },
        {
            urls: 'turn:172.236.136.45:443',
            username: 'f70015eec8deaa9ac60b9e9d',
            credential: 'JUdl1rA+ZXvisE3P'
        },
        {
            urls: 'turn:172.236.136.45:443?transport=tcp',
            username: 'f70015eec8deaa9ac60b9e9d',
            credential: 'JUdl1rA+ZXvisE3P'
        }
    ]
};

async function startWebRTCReceiver(uid, fullName, isFloating) {
    if (activePeerConnections[uid]) {
        closePeerConnection(uid);
    }

    const myUid = auth.currentUser ? auth.currentUser.uid : '';
    const myViewerId = myUid || 'viewer_' + Math.random().toString(36).substr(2, 9);

    console.log(`[WebRTC] Starting receiver for ${uid} (Floating: ${isFloating}, ViewerId: ${myViewerId})`);

    if (isFloating) {
        createDynamicFloatingPanel(uid, fullName);
    }

    try {
        const pc = new RTCPeerConnection(iceConfiguration);
        const remoteStream = new MediaStream();
        const pendingCandidates = [];
        let remoteDescSet = false;

        activePeerConnections[uid] = {
            pc: pc,
            remoteStream: remoteStream,
            isFloating: isFloating,
            connected: false,
            videoSender: null,
            audioSender: null,
            vcActive: false,
            audioUnmuted: true,
            viewerId: myViewerId
        };

        const viewerRef = ref(db, `streams/${uid}/viewers/${myViewerId}`);
        // Tulis ulang seluruh node viewer dengan timestamp agar menjamin trigger onChildChanged di HP
        // sekaligus membersihkan sdp & candidates sisa sesi sebelumnya.
        await set(viewerRef, {
            status: 'request',
            timestamp: Date.now()
        });

        const viewerStatusRef = ref(db, `streams/${uid}/viewers/${myViewerId}/status`);

        // Dengarkan perubahan status: kalau kembali jadi 'request', web sedang reinisialisasi signaling
        // Dalam kasus ini kita akan menghapus koneksi lama dan tidak perlu bereaksi — HP yang akan kirim offer baru
        activePeerConnections[uid].statusListener = onValue(viewerStatusRef, (snapshot) => {
            const status = snapshot.val();
            if (status === 'rejected_full') {
                alert(`Siaran Penuh: Jumlah penonton untuk ${fullName} sudah penuh (Maksimal 3 Komandan).`);
                closePeerConnection(uid);
            }
        });

        pc.ontrack = (event) => {
            console.log(`[WebRTC] Track received: ${event.track.kind}`);
            // Prevent duplicate tracks
            if (remoteStream.getTracks().some(t => t.id === event.track.id)) return;
            remoteStream.addTrack(event.track);

            // Dynamically check if this connection is currently floating or in grid
            const currentlyFloating = activePeerConnections[uid] && activePeerConnections[uid].isFloating;
            const videoEl = currentlyFloating
                ? document.getElementById(`live-float-video-${uid}`)
                : document.getElementById(`video-${uid}`);
            if (videoEl) {
                if (videoEl.srcObject === remoteStream) return;
                videoEl.srcObject = remoteStream;
                videoEl.muted = false;
                if (activePeerConnections[uid]) {
                    activePeerConnections[uid].audioUnmuted = true;
                }
                
                videoEl.play()
                    .then(() => {
                        console.log('[WebRTC] Autoplay succeeded with sound!');
                        const muteIcon = document.getElementById(`mute-icon-${uid}`);
                        if (muteIcon) muteIcon.className = 'fa-solid fa-volume-high';
                    })
                    .catch(e => {
                        console.warn('[WebRTC] Autoplay with sound blocked, muting to autoplay:', e);
                        videoEl.muted = true;
                        if (activePeerConnections[uid]) {
                            activePeerConnections[uid].audioUnmuted = false;
                        }
                        const muteIcon = document.getElementById(`mute-icon-${uid}`);
                        if (muteIcon) muteIcon.className = 'fa-solid fa-volume-xmark';
                        
                        // Retry playing muted (guaranteed to succeed)
                        videoEl.play().catch(playErr => {
                            console.error('[WebRTC] Muted autoplay failed too:', playErr);
                        });
                    });
            }

            if (currentlyFloating) {
                const loading = document.getElementById(`live-float-loading-${uid}`);
                if (loading) loading.style.display = 'none';
            }
        };

        const handleConnectedState = () => {
            const isConnected = pc.connectionState === 'connected' || pc.iceConnectionState === 'connected' || pc.iceConnectionState === 'completed';
            console.log(`[WebRTC] Evaluating connection status. ConnectionState: ${pc.connectionState}, IceConnectionState: ${pc.iceConnectionState}. Result isConnected: ${isConnected}`);
            if (activePeerConnections[uid]) {
                activePeerConnections[uid].connected = isConnected;
            }
            if (isConnected) {
                // Sembunyikan overlay loading saat terhubung
                const overlay = document.getElementById(`status-overlay-${uid}`);
                if (overlay) overlay.style.display = 'none';
                renderLiveGrid();
            }
        };

        pc.onconnectionstatechange = () => {
            console.log(`[WebRTC] Connection state change: ${pc.connectionState} | ICE state: ${pc.iceConnectionState}`);
            handleConnectedState();
            if (pc.connectionState === 'failed') {
                console.warn('[WebRTC] Connection failed, retrying...');
                setTimeout(() => {
                    const info = window.activeStreams[uid];
                    if (info) {
                        closePeerConnection(uid);
                        const name = ((info.pangkat || '').trim() + ' ' + (info.nama || '')).trim();
                        startWebRTCReceiver(uid, name, isFloating);
                    }
                }, 3000);
            }
        };

        pc.oniceconnectionstatechange = () => {
            console.log(`[WebRTC] ICE Connection state change: ${pc.iceConnectionState}`);
            handleConnectedState();
            if (pc.iceConnectionState === 'failed') {
                console.warn('[WebRTC] ICE Connection failed, retrying...');
                setTimeout(() => {
                    const info = window.activeStreams[uid];
                    if (info) {
                        closePeerConnection(uid);
                        const name = ((info.pangkat || '').trim() + ' ' + (info.nama || '')).trim();
                        startWebRTCReceiver(uid, name, isFloating);
                    }
                }, 3000);
            }
        };

        // (Answer dan receiver candidates lama sudah terhapus saat kita menimpa viewerRef di atas)
        pc.onicecandidate = (event) => {
            if (event.candidate) {
                console.log(`[WebRTC] Local ICE candidate: ${event.candidate.candidate.substring(0, 60)}...`);
                const candidateRef = push(ref(db, `streams/${uid}/viewers/${myViewerId}/candidates/receiver`));
                set(candidateRef, event.candidate.toJSON());
            } else {
                console.log('[WebRTC] ICE gathering complete (null candidate).');
            }
        };

        // Dengarkan ICE candidates dari streamer (HP)
        const streamerCandidatesRef = ref(db, `streams/${uid}/viewers/${myViewerId}/candidates/streamer`);
        activePeerConnections[uid].candidateListener = onChildAdded(streamerCandidatesRef, (snapshot) => {
            const c = snapshot.val();
            if (!c) return;
            console.log(`[WebRTC] Streamer candidate received`);
            const candidate = new RTCIceCandidate(c);
            if (remoteDescSet) {
                pc.addIceCandidate(candidate).catch(e => console.warn('[WebRTC] addIceCandidate error:', e));
            } else {
                pendingCandidates.push(candidate);
            }
        });

        // Dengarkan SDP Offer dari streamer (HP)
        const offerRef = ref(db, `streams/${uid}/viewers/${myViewerId}/sdp/offer`);
        activePeerConnections[uid].offerListener = onValue(offerRef, async (snapshot) => {
            const offerVal = snapshot.val();
            if (!offerVal || !offerVal.sdp) {
                console.log('[WebRTC] No offer found in Firebase yet, waiting...');
                return;
            }
            if (remoteDescSet) {
                console.log('[WebRTC] Offer already processed, skipping.');
                return;
            }

            console.log(`[WebRTC] Offer received, creating answer... (${pendingCandidates.length} pending candidates)`);
            try {
                await pc.setRemoteDescription(new RTCSessionDescription({ type: 'offer', sdp: offerVal.sdp }));
                remoteDescSet = true;

                // Ambil transceivers dari SDP Offer
                pc.getTransceivers().forEach(transceiver => {
                    transceiver.direction = 'sendrecv';
                    const kind = transceiver.receiver.track.kind;
                    if (kind === 'video') {
                        activePeerConnections[uid].videoSender = transceiver.sender;
                    } else if (kind === 'audio') {
                        activePeerConnections[uid].audioSender = transceiver.sender;
                    }
                });

                // Tambahkan candidates yang tertunda
                for (const cand of pendingCandidates) {
                    await pc.addIceCandidate(cand).catch(e => console.warn('[WebRTC] pending addIceCandidate error:', e));
                }
                console.log(`[WebRTC] Added ${pendingCandidates.length} pending candidates.`);
                pendingCandidates.length = 0;

                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);

                await set(ref(db, `streams/${uid}/viewers/${myViewerId}/sdp/answer`), {
                    type: answer.type,
                    sdp: answer.sdp
                });
                console.log('[WebRTC] Answer sent!');
            } catch (e) {
                console.error('[WebRTC] Error processing offer:', e);
            }
        });

        renderLiveGrid();

    } catch (e) {
        console.error('[WebRTC] Establishment failed:', e);
        closePeerConnection(uid);
    }
}

function closePeerConnection(uid, shouldStopStreamOnMobile = false) {
    if (window.webRecorders && window.webRecorders[uid]) {
        try {
            window.webRecorders[uid].stop();
        } catch (e) {
            console.error('Error stopping web recorder during peer connection closure:', e);
        }
        delete window.webRecorders[uid];
    }

    if (window.focusedStreamUids) {
        const idx = window.focusedStreamUids.indexOf(uid);
        if (idx > -1) {
            window.focusedStreamUids.splice(idx, 1);
        }
    }

    const conn = activePeerConnections[uid];
    if (!conn) return;

    console.log(`Closing peer connection for ${uid}`);

    // Jika admin klik Hentikan → matikan live di HP juga
    if (shouldStopStreamOnMobile) {
        set(ref(db, `streams/${uid}/info/active`), false);
        console.log(`[WebRTC] Admin menghentikan live HP: ${uid}`);
    }

    // Bersihkan status VC
    set(ref(db, `streams/${uid}/info/vcActive`), null);
    set(ref(db, `streams/${uid}/info/vcVideoActive`), null);

    if (conn.candidateListener) conn.candidateListener();
    if (conn.offerListener) conn.offerListener();
    if (conn.statusListener) conn.statusListener();

    if (conn.viewerId) {
        remove(ref(db, `streams/${uid}/viewers/${conn.viewerId}`));
    }

    if (conn.pc) {
        conn.pc.close();
    }

    const videoEl = conn.isFloating ?
        document.getElementById(`live-float-video-${uid}`) :
        document.getElementById(`video-${uid}`);
    if (videoEl) {
        videoEl.srcObject = null;
    }

    // Reset mute icon when connection closes
    if (!conn.isFloating) {
        const muteIcon = document.getElementById(`mute-icon-${uid}`);
        if (muteIcon) muteIcon.className = 'fa-solid fa-volume-xmark';
    }

    if (conn.isFloating) {
        const panel = document.getElementById(`live-floating-panel-${uid}`);
        if (panel) panel.remove();
    }

    delete activePeerConnections[uid];

    // Clean up local camera/mic if no other peer connection is using VC
    const anyActiveVC = Object.values(activePeerConnections).some(c => c.vcActive);
    if (!anyActiveVC && window.localVCStream) {
        window.localVCStream.getTracks().forEach(t => t.stop());
        window.localVCStream = null;
    }
}


// ============================================================
// SEARCH LOCATION ON TACTICAL MAP (NOMINATIM API)
// ============================================================
document.addEventListener('DOMContentLoaded', () => {
    const inputLocation = document.getElementById('map-location-search');
    const btnSearch = document.getElementById('btn-search-location');
    const btnClear = document.getElementById('btn-clear-location-search');
    const dropdownResults = document.getElementById('map-location-results');

    if (!inputLocation || !btnSearch || !dropdownResults) return;

    let searchTimeout = null;

    inputLocation.addEventListener('input', () => {
        if (inputLocation.value.trim().length > 0) {
            if (btnClear) btnClear.style.display = 'block';
        } else {
            if (btnClear) btnClear.style.display = 'none';
            dropdownResults.style.display = 'none';
        }

        clearTimeout(searchTimeout);
        searchTimeout = setTimeout(performLocationSearch, 800);
    });

    btnSearch.addEventListener('click', performLocationSearch);

    if (btnClear) {
        btnClear.addEventListener('click', () => {
            inputLocation.value = '';
            btnClear.style.display = 'none';
            dropdownResults.style.display = 'none';
        });
    }

    document.addEventListener('click', (e) => {
        if (!e.target.closest('.floating-location-search')) {
            dropdownResults.style.display = 'none';
        }
    });

    async function performLocationSearch() {
        const query = inputLocation.value.trim();
        if (query.length < 3) {
            dropdownResults.style.display = 'none';
            return;
        }

        dropdownResults.innerHTML = '<div style="padding: 10px; color: var(--text-muted); text-align: center;"><i class="fa-solid fa-circle-notch fa-spin me-2"></i>Mencari lokasi...</div>';
        dropdownResults.style.display = 'block';

        try {
            // Priority viewbox around South Kalimantan: Lat: -4.5 to -1.5, Lng: 114.0 to 116.5
            const url = `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&countrycodes=id&viewbox=114.0,-4.5,116.5,-1.5&limit=5`;
            const res = await fetch(url, {
                headers: {
                    'Accept-Language': 'id-ID,id;q=0.9,en;q=0.8'
                }
            });
            const data = await res.json();

            if (!data || data.length === 0) {
                dropdownResults.innerHTML = '<div style="padding: 10px; color: var(--text-muted); text-align: center;"><i class="fa-solid fa-circle-exclamation me-2"></i>Lokasi tidak ditemukan.</div>';
                return;
            }

            dropdownResults.innerHTML = '';
            data.forEach(item => {
                const displayName = item.display_name;
                const lat = parseFloat(item.lat);
                const lon = parseFloat(item.lon);

                const itemDiv = document.createElement('div');
                itemDiv.className = 'location-search-item';
                itemDiv.style.padding = '8px 12px';
                itemDiv.style.cursor = 'pointer';
                itemDiv.style.borderBottom = '1px solid var(--border-color)';
                itemDiv.style.color = 'var(--text-main)';
                itemDiv.innerHTML = `
                    <div style="font-weight: bold; font-size: 11px;"><i class="fa-solid fa-location-dot text-primary me-2"></i>${displayName.split(',')[0]}</div>
                    <div style="font-size: 10px; color: var(--text-muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; margin-top: 2px;">${displayName}</div>
                `;

                itemDiv.addEventListener('mouseenter', () => {
                    itemDiv.style.backgroundColor = 'var(--table-hover)';
                });
                itemDiv.addEventListener('mouseleave', () => {
                    itemDiv.style.backgroundColor = '';
                });

                itemDiv.addEventListener('click', () => {
                    if (typeof map !== 'undefined') {
                        map.setView([lat, lon], 16);
                        
                        const searchMarker = L.marker([lat, lon]).addTo(map);
                        searchMarker.bindPopup(`<strong>Lokasi Terpilih:</strong><br>${displayName}`).openPopup();
                        
                        searchMarker.on('popupclose', () => {
                            map.removeLayer(searchMarker);
                        });
                    }
                    dropdownResults.style.display = 'none';
                    if (btnClear) btnClear.style.display = 'block';
                });

                dropdownResults.appendChild(itemDiv);
            });
        } catch (err) {
            console.error('Location search error:', err);
            dropdownResults.innerHTML = '<div style="padding: 10px; color: var(--text-muted); text-align: center;"><i class="fa-solid fa-triangle-exclamation text-danger me-2"></i>Gagal melakukan pencarian.</div>';
        }
    }
});

