const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { ref, get, set } = require('firebase/database');

let testEnv;

describe('Firebase Realtime Database Security Rules Unit Tests', () => {
    beforeAll(async () => {
        // Inisialisasi lingkungan pengujian emulator dengan aturan keamanan lokal
        testEnv = await initializeTestEnvironment({
            projectId: "siaga-polda-kalsel",
            database: {
                rules: fs.readFileSync(path.resolve(__dirname, 'database.rules.json'), 'utf8'),
                host: "127.0.0.1",
                port: 9000
            }
        });
    });

    afterAll(async () => {
        await testEnv.cleanup();
    });

    beforeEach(async () => {
        // Bersihkan data database sebelum setiap skenario uji berjalan
        await testEnv.clearDatabase();
    });

    test('1. Skenario: Pengguna tanpa login (unauthenticated) harus ditolak dari semua akses', async () => {
        const unauthedDb = testEnv.unauthenticatedContext().database();
        
        // Membaca chat umum tanpa login harus gagal
        await assertFails(get(ref(unauthedDb, 'chat/umum')));
        
        // Menulis status pelacakan tanpa login harus gagal
        await assertFails(set(ref(unauthedDb, 'live_tracking/POL-12345'), {
            koordinat: { lat: -3.4428, lng: 114.8306 },
            waktu: new Date().toISOString(),
            nrp: '12345'
        }));
    });

    test('2. Skenario: Anggota aktif dapat membaca data publik dan mengirim pesan obrolan umum dengan format valid', async () => {
        const myUid = 'user_anggota_001';
        
        // Seed data profil anggota dengan status aktif menggunakan admin context (bypass rules)
        await testEnv.withSecurityRulesDisabled(async (context) => {
            const adminDb = context.database();
            await set(ref(adminDb, `users/${myUid}`), {
                nama: 'Zainal Haqi',
                nrp: '2301402039',
                status: 'active',
                role: 'member'
            });
        });

        const authedDb = testEnv.authenticatedContext(myUid).database();

        // Anggota aktif harus diizinkan membaca daftar pengguna
        await assertSucceeds(get(ref(authedDb, 'users')));

        // Anggota aktif mengirim pesan dengan format lengkap dan valid -> harus sukses
        await assertSucceeds(set(ref(authedDb, 'chat/umum/msg_001'), {
            uid: myUid,
            nrp: '2301402039',
            nama: 'Zainal Haqi',
            pangkat: 'Bripda',
            pesan: 'Melaporkan situasi aman terkendali.',
            waktu: new Date().toISOString()
        }));

        // Anggota aktif mengirim pesan dengan format salah (data tidak lengkap) -> harus ditolak
        await assertFails(set(ref(authedDb, 'chat/umum/msg_002'), {
            pesan: 'Data tidak lengkap'
            // Kurang field uid, nrp, nama, pangkat, waktu
        }));
    });

    test('3. Skenario: Hak akses DM (Pesan Pribadi) hanya boleh diakses oleh partisipan terdaftar', async () => {
        const convId = 'conversation_abc_123';
        const userA = 'user_a';
        const userB = 'user_b';
        const intruder = 'user_c_penyusup';

        // Seed data obrolan DM dengan partisipan terdaftar: User A dan User B
        await testEnv.withSecurityRulesDisabled(async (context) => {
            const adminDb = context.database();
            await set(ref(adminDb, `chat/dm/${convId}`), {
                participants: {
                    [userA]: true,
                    [userB]: true
                },
                lastMessage: 'Halo',
                updatedAt: Date.now()
            });

            // Set status pengguna aktif untuk User A, User B, dan Intruder
            await set(ref(adminDb, `users/${userA}/status`), 'active');
            await set(ref(adminDb, `users/${userB}/status`), 'active');
            await set(ref(adminDb, `users/${intruder}/status`), 'active');
        });

        const dbUserA = testEnv.authenticatedContext(userA).database();
        const dbIntruder = testEnv.authenticatedContext(intruder).database();

        // User A (anggota terdaftar) harus diperbolehkan membaca chat DM
        await assertSucceeds(get(ref(dbUserA, `chat/dm/${convId}`)));

        // Intruder (bukan partisipan) mencoba membaca chat DM -> harus gagal (ditolak aturan keamanan)
        await assertFails(get(ref(dbIntruder, `chat/dm/${convId}`)));
    });
});
