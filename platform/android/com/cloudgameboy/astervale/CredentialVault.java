package com.cloudgameboy.astervale;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import org.json.JSONObject;

/** App-private, backup-excluded ciphertext; the AES key never leaves AndroidKeyStore. */
public final class CredentialVault {
    private static final String ALIAS = "astervale.remembered-login.v1";
    private final AtomicFile file;
    private final byte[] aad;
    public CredentialVault(Context context) {
        file = new AtomicFile(new File(context.getNoBackupFilesDir(), "remembered-login.bin"));
        aad = (context.getPackageName()+":remembered-login:v1").getBytes(StandardCharsets.UTF_8);
    }
    private SecretKey key(boolean create) throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(ALIAS)) return (SecretKey)store.getKey(ALIAS, null);
        if (!create) return null;
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).setRandomizedEncryptionRequired(true).build());
        return generator.generateKey();
    }
    public synchronized boolean save(String host, int port, String username, String password) {
        if (host.isEmpty() || host.length()>512 || port<1 || port>65535 || username.isEmpty() || username.length()>16 || password.isEmpty() || password.length()>64) return false;
        FileOutputStream output = null;
        try {
            JSONObject data = new JSONObject(); data.put("host",host);data.put("port",port);data.put("username",username);data.put("password",password);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key(true));cipher.updateAAD(aad);
            byte[] iv=cipher.getIV(), encrypted=cipher.doFinal(data.toString().getBytes(StandardCharsets.UTF_8));
            output=file.startWrite();output.write(ByteBuffer.allocate(1+iv.length+encrypted.length).put((byte)iv.length).put(iv).put(encrypted).array());file.finishWrite(output);return true;
        } catch (Exception ignored) { if (output!=null)file.failWrite(output); return false; }
    }
    public synchronized String load() {
        if (!file.getBaseFile().exists()) return "";
        try (FileInputStream input=file.openRead()) {
            if (input.getChannel().size()>16384) throw new IllegalStateException();
            byte[] bytes=new byte[(int)input.getChannel().size()];int offset=0;
            while (offset<bytes.length) { int count=input.read(bytes,offset,bytes.length-offset);if(count<0)throw new IllegalStateException();offset+=count; }
            if (bytes.length<30 || bytes[0]!=12) throw new IllegalStateException();
            SecretKey secret=key(false);if(secret==null)throw new IllegalStateException();
            Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,secret,new GCMParameterSpec(128,bytes,1,12));cipher.updateAAD(aad);
            String decoded=new String(cipher.doFinal(bytes,13,bytes.length-13),StandardCharsets.UTF_8);
            JSONObject json=new JSONObject(decoded);
            if(!json.has("host") || !json.has("port") || !json.has("username") || !json.has("password"))throw new IllegalStateException();
            return decoded;
        } catch(Exception ignored) { clear();return ""; }
    }
    public synchronized boolean clear() {
        file.delete();
        try { KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);store.deleteEntry(ALIAS);return !file.getBaseFile().exists(); }
        catch(Exception ignored) {return false;}
    }
}
