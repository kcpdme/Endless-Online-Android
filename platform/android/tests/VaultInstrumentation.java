package com.cloudgameboy.astervale.vaulttest;
import android.app.Instrumentation;
import android.os.Bundle;
import com.cloudgameboy.astervale.CredentialVault;
import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;

public final class VaultInstrumentation extends Instrumentation {
    private String phase;
    @Override public void onCreate(Bundle args) {super.onCreate(args);phase=args.getString("phase","first");start();}
    private static void require(boolean value) {if(!value)throw new AssertionError();}
    @Override public void onStart() {
        Bundle result=new Bundle();
        try {
            CredentialVault vault=new CredentialVault(getTargetContext());
            File file=new File(getTargetContext().getNoBackupFilesDir(),"remembered-login.bin");
            if(phase.equals("first")) {
                require(vault.clear());require(vault.load().isEmpty());
                require(vault.save("wss://example.invalid/ws",8079,"devvault","PrivateTestPassword42"));
                byte[] a=Files.readAllBytes(file.toPath());require(!new String(a,java.nio.charset.StandardCharsets.ISO_8859_1).contains("PrivateTestPassword42"));
                require(vault.load().contains("PrivateTestPassword42"));
                require(vault.save("wss://example.invalid/ws",8079,"devvault","PrivateTestPassword42"));
                byte[] b=Files.readAllBytes(file.toPath());require(!Arrays.equals(a,b));
            } else {
                require(vault.load().contains("PrivateTestPassword42"));
                byte[] tampered=Files.readAllBytes(file.toPath());tampered[tampered.length-1]^=1;Files.write(file.toPath(),tampered);
                require(vault.load().isEmpty());require(!file.exists());
                require(vault.save("wss://second.invalid/ws",8079,"otherdev","DifferentTestPassword"));
                require(vault.clear());require(vault.load().isEmpty());require(!file.exists());
            }
            result.putString("result","passed");result.putString("phase",phase);finish(-1,result);
        } catch(Throwable ignored) {result.putString("result","failed");finish(0,result);}
    }
}
