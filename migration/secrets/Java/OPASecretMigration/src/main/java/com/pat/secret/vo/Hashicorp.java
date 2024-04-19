package com.pat.secret.vo;

import java.util.ArrayList;
import java.util.List;

/**
 * Object to load Hashicorp vault specific properties from property file
 * @author rajeshkumar
 *
 */

public class Hashicorp {

	private String host;
	private String port;
	private String scheme;
	private String token;
	private String secretengine;
	private String metadata;

	public String getHost() {
		return host;
	}

	public void setHost(String host) {
		this.host = host;
	}

	public String getPort() {
		return port;
	}

	public void setPort(String port) {
		this.port = port;
	}

	public String getScheme() {
		return scheme;
	}

	public void setScheme(String scheme) {
		this.scheme = scheme;
	}

	public String getToken() {
		return token;
	}

	public void setToken(String token) {
		this.token = token;
	}

	public String getSecretengine() {
		return secretengine;
	}

	public void setSecretengine(String secretengine) {
		this.secretengine = secretengine;
	}

	public List<String> getSecretengineList() {
		String[] convertedEngineArray = getSecretengine().split(",");
		List<String> convertedEngineList = new ArrayList<String>();
		for (String engine : convertedEngineArray) {
			convertedEngineList.add((engine.trim()));
		}
		return convertedEngineList;
	}

	public String getMetadata() {
		return metadata;
	}

	public void setMetadata(String metadata) {
		this.metadata = metadata;
	}

	@Override
	public String toString() {
		return "Hashicorp [host=" + host + ", port=" + port + ", scheme=" + scheme + ", token=" + token
				+ ", secretengine=" + secretengine + ", metadata=" + metadata + "]";
	}

}
