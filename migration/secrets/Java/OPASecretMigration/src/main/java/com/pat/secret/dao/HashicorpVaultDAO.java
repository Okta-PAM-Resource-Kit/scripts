package com.pat.secret.dao;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.vault.authentication.TokenAuthentication;
import org.springframework.vault.client.VaultEndpoint;
import org.springframework.vault.core.VaultTemplate;
import org.springframework.vault.support.VaultResponse;

/**
 * This object connect with Hashicorp vault to retrieve vaulted data
 * @author rajeshkumar
 *
 */

@Component
public class HashicorpVaultDAO {

	// Logger
	private static final Logger LOGGER = LoggerFactory.getLogger(HashicorpVaultDAO.class);

	public HashicorpVaultDAO() {

	}

	/**
	 * Get all metadata for Secret Engine
	 * 
	 * @return
	 */
	public List<String> getSecretMetadata(String host, String port, String scheme, String authToken,
			String secretEngine, String metadataEndpoint) {
		LOGGER.info("getSecretMetadata Getting Hashicorp Vault Secret Engine Metadata");
		List<String> listResponse = new ArrayList<String>(5);
		try {
			VaultEndpoint vaultEndpoint = new VaultEndpoint();
			vaultEndpoint.setHost(host);
			vaultEndpoint.setPort(Integer.parseInt(port));
			vaultEndpoint.setScheme(scheme);

			// Authenticate
			VaultTemplate vaultTemplate = new VaultTemplate(vaultEndpoint, new TokenAuthentication(authToken));
			listResponse = vaultTemplate.list(secretEngine + "/" + metadataEndpoint + "/");

		} catch (Exception e) {
			LOGGER.error("getSecretMetadata >>> "+e.getMessage());
			//e.printStackTrace();
		}
		LOGGER.info("getSecretMetadata Available secrets Path ---> " + listResponse);
		return listResponse;

	}

	/**
	 * Get all metadata for Secret Engine
	 * 
	 * @return
	 */
	public Map<String,Object> getSecrets(String host, String port, String scheme, String authToken,
			String secretEngine, String path) {
		LOGGER.info("getSecrets Getting Hashicorp Vault Secret");
		Map<String,Object> hashiVaultSecrets = new HashMap<String, Object>(1);
		try {
			VaultEndpoint vaultEndpoint = new VaultEndpoint();
			vaultEndpoint.setHost(host);
			vaultEndpoint.setPort(Integer.parseInt(port));
			vaultEndpoint.setScheme(scheme);
			// Authenticate
			VaultTemplate vaultTemplate = new VaultTemplate(vaultEndpoint, new TokenAuthentication(authToken));
			// Reading a secret
			VaultResponse readResponse = vaultTemplate.read(secretEngine + "/data/" + path);
			hashiVaultSecrets = readResponse.getData();
		} catch (Exception e) {
			LOGGER.error("getSecrets >>> "+e.getMessage());
			//e.printStackTrace();
		}
		return hashiVaultSecrets;
	}

}
