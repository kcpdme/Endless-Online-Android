package com.cloudgameboy.astervale;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

public final class AsterCredentials extends GodotPlugin {
    private final CredentialVault vault;
    public AsterCredentials(Godot godot) { super(godot);vault=new CredentialVault(godot.getActivity().getApplicationContext()); }
    @Override public String getPluginName() { return "AsterCredentials"; }
    @UsedByGodot public String loadCredentials() { return vault.load(); }
    @UsedByGodot public boolean saveCredentials(String host,int port,String username,String password) { return vault.save(host,port,username,password); }
    @UsedByGodot public boolean clearCredentials() { return vault.clear(); }
}
