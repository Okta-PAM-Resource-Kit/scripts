package com.pat.secret.bo;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nimbusds.jose.EncryptionMethod;
import com.nimbusds.jose.JWEAlgorithm;
import com.nimbusds.jose.JWEHeader;
import com.nimbusds.jose.JWEObject;
import com.nimbusds.jose.Payload;
import com.nimbusds.jose.crypto.RSAEncrypter;
import com.nimbusds.jose.jwk.JWK;
import com.nimbusds.jose.jwk.RSAKey;
import com.pat.secret.dao.HashicorpVaultDAO;
import com.pat.secret.dao.OPASecretServicesDAO;
import com.pat.secret.utility.OPASecretUtility;
import com.pat.secret.utility.RegisterProperties;
import com.pat.secret.vo.Hashicorp;
import com.pat.secret.vo.OPAVaultRequest;
import com.pat.secret.vo.OPAVaultResponse;

/**
 * This is business Object to migrate hashicorp secrets into Okta vault
 * 
 * @author rajeshkumar
 *
 */

@Component
public class OPASecretServicesBO {

	private static OPASecretUtility opaSecretUtility;

	private static OPASecretServicesDAO opaSecretServicesDAO;

	private static HashicorpVaultDAO hashicorpVaultDAO;

	private static RegisterProperties regProps;

	@Autowired
	private void setRegister(RegisterProperties regProps) {
		OPASecretServicesBO.regProps = regProps;
	}

	@Autowired
	private void setRegister(OPASecretUtility opaSecretUtility) {
		OPASecretServicesBO.opaSecretUtility = opaSecretUtility;
	}

	@Autowired
	private void setOPASecretServicesDAO(OPASecretServicesDAO opaSecretServicesDAO) {
		OPASecretServicesBO.opaSecretServicesDAO = opaSecretServicesDAO;
	}

	@Autowired
	private void setHashicorpVaultDAO(HashicorpVaultDAO hashicorpVaultDAO) {
		OPASecretServicesBO.hashicorpVaultDAO = hashicorpVaultDAO;
	}

	// Logger
	private static final Logger LOGGER = LoggerFactory.getLogger(OPASecretServicesBO.class);

	static String authToken = "";
	static String publicKeyDetails = "";
	static JWK key = null;
	static RSAKey rsaPublicJWK = null;
	static JWEHeader header = null;
	static RSAEncrypter encrypter = null;

	public OPASecretServicesBO() {

	}

	@PostConstruct
	private void postConstruct() {
		LOGGER.info("OPASecretServicesBO postConstruct");
		try {
			getUserAuthToken();
			getJWKSPublicKey();
			// Get Okta Vault public key
			key = JWK.parse(publicKeyDetails);
			LOGGER.info("JWK key ====>>>  " + key);
			rsaPublicJWK = RSAKey.parse(publicKeyDetails);
			// Prepare the header to make to send in as request header
			header = new JWEHeader.Builder(JWEAlgorithm.RSA_OAEP_256, EncryptionMethod.A256GCM)
					.keyID(rsaPublicJWK.getKeyID()).contentType("text/plain") // Set the content type
					.build();
			// prepare RSAEncrypter object using public key
			encrypter = new RSAEncrypter(rsaPublicJWK);
		} catch (Exception e) {
			LOGGER.error("postConstruct >>> " + e.getMessage());
			// e.printStackTrace();
		}

	}

	/**
	 * Get Auth token to use OPA API
	 */
	private static void getUserAuthToken() {
		LOGGER.info("OPASecretServicesBO getUserAuthToken Retrieve auth token");
		String requestBody = "";
		String apiEndpointURL = "";
		try {
			apiEndpointURL = opaSecretUtility.getTokenAPIEndpoint();
			LOGGER.debug("getUserAuthToken apiEndpointURL ---> " + apiEndpointURL);
			requestBody = opaSecretUtility.getAPITokenRequestBody();
			LOGGER.debug("getUserAuthToken requestBody ---> " + requestBody);
			authToken = opaSecretServicesDAO.getUserAuthToken(apiEndpointURL, requestBody);
		} catch (Exception e) {
			LOGGER.error("getUserAuthToken >>> " + e.getMessage());
			// e.printStackTrace();
		}
	}

	/**
	 * Get JWKS Public key from OPA
	 */
	private static void getJWKSPublicKey() {
		LOGGER.info("OPASecretServicesBO getJWKSPublicKey get OPA public key");
		String apiEndpointURL = "";
		try {
			apiEndpointURL = opaSecretUtility.getJWKSAPIEndpoint();
			LOGGER.debug("getJWKSPublicKey apiEndpointURL ---> " + apiEndpointURL);
			LOGGER.debug("getJWKSPublicKey authToken ---> " + authToken);
			publicKeyDetails = opaSecretServicesDAO.getVaultPublicKey(apiEndpointURL, authToken);
		} catch (Exception e) {
			LOGGER.error("getJWKSPublicKey >>> " + e.getMessage());
			// e.printStackTrace();
		}
		LOGGER.info("OPASecretServicesBO::getJWKSPublicKey::publicKeyDetails ---> " + publicKeyDetails);
	}

	/**
	 * Read secret from Hashicorp and Create secret in Okta vault Mapping Hashicorp
	 * engine as folder and metadata as secret
	 */
	@SuppressWarnings("unchecked")
	public void migrateHashicorpSecret() {
		LOGGER.info("migrateHashicorpSecret Start Secret Creation process in OPA");
		String secretName = "";
		String secretData = "";
		String secretFolderId = "";
		Hashicorp hashicorp = null;
		OPAVaultResponse opaSecretVaultResponse = null;
		List<String> listResponse = new ArrayList<String>(5);
		Map<String, Object> hashiVaultSecrets = new HashMap<String, Object>(1);
		Map<String, String> vaultSecret = new HashMap<String, String>(1);
		List<String> secretEnginesList = new ArrayList<String>(5);
		try {
			// Get Hashicorp Environment details
			hashicorp = opaSecretUtility.getHashicorpEnvironmentDetails();
			// Get the list of Secret Engines to interact with
			secretEnginesList = hashicorp.getSecretengineList();
			LOGGER.info("migrateHashicorpSecret secretEnginesList  ==>>>  " + secretEnginesList);
			for (String secretEngine : secretEnginesList) {
				// Create folder for each secret engine
				opaSecretVaultResponse = createSecretFolder(secretEngine);
				// Retrieve Secret Folder Id
				secretFolderId = opaSecretVaultResponse.getNewObjectId();
				// Get Secret metadata from Hashicorp
				listResponse = getSecretMetadata(hashicorp, secretEngine);
				for (String name : listResponse) {
					secretName = name;
					LOGGER.info("migrateHashicorpSecret  ===>>>  " + secretName);
					hashiVaultSecrets = hashicorpVaultDAO.getSecrets(hashicorp.getHost(), hashicorp.getPort(),
							hashicorp.getScheme(), hashicorp.getToken(), secretEngine, secretName);
					if (hashiVaultSecrets.size() > 0) {
						vaultSecret = (Map<String, String>) hashiVaultSecrets.get("data");
						//Below logger writes credential in log (Not recommended to uncomment)
						//LOGGER.debug("migrateHashicorpSecret vaultSecret ======== " + vaultSecret);
						ObjectMapper secretDataObj = new ObjectMapper();
						secretData = secretDataObj.writeValueAsString(vaultSecret);
						createSecret(secretData, secretName, secretFolderId, secretEngine);
					}
				}
			}

		} catch (Exception e) {
			LOGGER.error("migrateHashicorpSecret >>> " + e.getMessage());
			// e.printStackTrace();
		}
	}

	/**
	 * Create Secret
	 * 
	 * @param secretData
	 * @param secretName
	 * @param folderId
	 * @param secretEngine
	 */
	private void createSecret(String secretData, String secretName, String folderId, String secretEngine) {
		LOGGER.info("createSecret Create secret in OPA");
		String apiEndpointURL = "";
		String secretPayloadOPA = "";
		OPAVaultRequest opaVaultRequest = null;
		ObjectMapper opaPayloadObj = null;
		//
		try {
			apiEndpointURL = opaSecretUtility.getCreateSecretAPIEndpoint();
			LOGGER.debug("createSecret apiEndpointURL: " + apiEndpointURL);
			Payload payload = new Payload(secretData);
			JWEObject encrypted_data = new JWEObject(header, payload);
			encrypted_data.encrypt(encrypter);
			// Serialize the JWE to compact form
			String jweString = encrypted_data.serialize();
			// Set the request payload to create secret
			opaVaultRequest = new OPAVaultRequest();
			opaVaultRequest.setSecretJwe(jweString);
			opaVaultRequest.setSecretDescription(regProps.getOktapam().getSecretFolderDesc());
			opaVaultRequest.setParentFolderId(folderId);
			opaVaultRequest.setName(secretName);
			opaPayloadObj = new ObjectMapper();
			secretPayloadOPA = opaPayloadObj.writeValueAsString(opaVaultRequest);
			LOGGER.debug("createSecret secretPayloadOPA: -->>> " + secretPayloadOPA);
			// Create Secret
			opaSecretServicesDAO.createOPASecret(secretPayloadOPA, apiEndpointURL, authToken);
		} catch (Exception e) {
			LOGGER.error("createSecret >>> " + e.getMessage());
			// e.printStackTrace();
		}
	}

	/**
	 * Create a folder to store secrets
	 * 
	 * @param secretEngine
	 * @return OPAVaultResponse - Secret folder response details with folder id
	 */
	private OPAVaultResponse createSecretFolder(String secretEngine) {
		LOGGER.info("createSecretFolder Create secret folder in OPA");
		OPAVaultRequest opaVaultRequest = null;
		ObjectMapper opaPayloadObj = new ObjectMapper();
		String folderPayloadOPA = "";
		OPAVaultResponse opaSecretVaultResponse = null;
		String apiEndpointURL = "";
		try {
			// Get the Create folder API endpoint
			apiEndpointURL = opaSecretUtility.getCreateFolderAPIEndpoint();
			LOGGER.debug("createSecretFolder apiEndpointURL: " + apiEndpointURL);
			// Set Object payload to create folder
			opaVaultRequest = new OPAVaultRequest();
			opaVaultRequest.setSecretDescription(regProps.getOktapam().getSecretFolderDesc());
			opaVaultRequest.setParentFolderId(regProps.getOktapam().getParentSecretFolderId());
			opaVaultRequest.setName(secretEngine);
			// Convert Object in Json Object format for request payload
			opaPayloadObj = new ObjectMapper();
			folderPayloadOPA = opaPayloadObj.writeValueAsString(opaVaultRequest);
			LOGGER.debug("createSecretFolder folderPayloadOPA: " + folderPayloadOPA);
			// Create folder as Secret Engines
			opaSecretVaultResponse = opaSecretServicesDAO.createOPASecretFolder(folderPayloadOPA, apiEndpointURL,
					authToken);
		} catch (Exception e) {
			LOGGER.error("createSecretFolder >>> " + e.getMessage());
			// e.printStackTrace();
		}
		return opaSecretVaultResponse;
	}

	/**
	 * Retrieve Hashicorp Secret Engine metadata
	 * 
	 * @return
	 */
	private List<String> getSecretMetadata(Hashicorp hashicorp, String secretEngine) {
		LOGGER.info("getSecretMetadata Retrieve Hashicorp secret engine metadata");
		List<String> listResponse = new ArrayList<String>(5);
		try {
			listResponse = hashicorpVaultDAO.getSecretMetadata(hashicorp.getHost(), hashicorp.getPort(),
					hashicorp.getScheme(), hashicorp.getToken(), secretEngine, hashicorp.getMetadata());
		} catch (Exception e) {
			LOGGER.error("getSecretMetadata >>> " + e.getMessage());
			// e.printStackTrace();
		}
		return listResponse;
	}

}
