package com.pat.secret.dao;

import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pat.secret.utility.Constants;
import com.pat.secret.vo.JWKSPublicKey;
import com.pat.secret.vo.OPAAuthTokenDetails;
import com.pat.secret.vo.OPAVaultResponse;

import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

/**
 * This object connects with Okta vault to create secrets retrieved from Hashicorp vault
 * @author rajeshkumar
 *
 */

@Component
public class OPASecretServicesDAO {

	// Logger
	private static final Logger LOGGER = LoggerFactory.getLogger(OPASecretServicesDAO.class);

	public OPASecretServicesDAO() {

	}

	/**
	 * Fetch Auth Token
	 * 
	 * @param apiEndpointURL
	 * @param requestBody
	 * @return Authorization Token for API Use
	 */
	public String getUserAuthToken(String apiEndpointURL, String requestBody) {
		LOGGER.info("getUserAuthToken Start Auth token retrieval process from Okta");
		String bearerToken = "";
		OPAAuthTokenDetails opaAuthTokenDetails = null;
		try {
			String responseBody = getAuthToken(apiEndpointURL, requestBody);
			LOGGER.debug("getUserAuthToken responseBody =====> " + responseBody);
			ObjectMapper mapper = new ObjectMapper();
			opaAuthTokenDetails = mapper.readValue(responseBody, OPAAuthTokenDetails.class);			
			bearerToken = opaAuthTokenDetails.getBearer_token();
		} catch (Exception e) {
			LOGGER.error("getUserAuthToken >>> "+ e.getMessage());
			//e.printStackTrace();
		}
		LOGGER.debug("getUserAuthToken bearerToken ===> " + bearerToken);
		return bearerToken;
	}

	/**
	 * Get JWKS Public Key
	 * 
	 * @param apiEndpointURL
	 * @param requestBody
	 * @return JWKS Public Key
	 */
	public String getVaultPublicKey(String apiEndpointURL, String authToken) {
		LOGGER.info("getVaultPublicKey Get Vault Public Key from Okta");
		OPAAuthTokenDetails opaAuthTokenDetails = null;
		JWKSPublicKey jwksPublicKey = null;
		String jwksPublicKeyJson = "";
		List<JWKSPublicKey> publicKeys = new ArrayList<JWKSPublicKey>(2);
		try {
			// Response from OktaPA after JWKS API endpoint call
			String responseBody = getVaultJWKS(apiEndpointURL, authToken);
			LOGGER.debug("getVaultPublicKey responseBody ===========> " + responseBody);
			// Mapping Response to POJO
			ObjectMapper mapper = new ObjectMapper();
			opaAuthTokenDetails = mapper.readValue(responseBody, OPAAuthTokenDetails.class);
			// Retreiving List from Object
			publicKeys = opaAuthTokenDetails.getVaultPublicKey();
			// Getting first key from the list. There is only one Key but response is always
			// in List format
			jwksPublicKey = publicKeys.get(0);
			LOGGER.debug("getVaultPublicKey jwksPublicKey kid ======> " + jwksPublicKey.getKid());
			// Converting JWKSPublicKey in Stringified Json format
			ObjectMapper Obj = new ObjectMapper();
			jwksPublicKeyJson = Obj.writeValueAsString(jwksPublicKey);
			LOGGER.debug("getVaultPublicKey jwksPublicKeyJson ========> " + jwksPublicKeyJson);
		} catch (Exception e) {
			LOGGER.error("getVaultPublicKey >>> "+ e.getMessage());
			// e.printStackTrace();
		}
		// If Size of Keys are coming more than Alarm!
		LOGGER.debug("getVaultPublicKey jwksPublicKey size ===> " + opaAuthTokenDetails.getVaultPublicKey().size());
		return jwksPublicKeyJson;
	}

	/**
	 * Create secret in Okta Vault
	 * 
	 * @param opaPASecretVault
	 * @param apiEndpoint
	 * @param authToken
	 * @return Response from Okta Vault after Secret Creation
	 */
	public OPAVaultResponse createOPASecret(String opaPASecretVault, String apiEndpoint, String authToken) {
		LOGGER.info("createOPASecret Start Create Secret process");
		OPAVaultResponse opaVaultResponse = null;
		try {
			String responseBody = createSecret(opaPASecretVault, apiEndpoint, authToken);
			LOGGER.debug("createOPASecret responseBody =============> " + responseBody);
			ObjectMapper mapper = new ObjectMapper();
			opaVaultResponse = mapper.readValue(responseBody, OPAVaultResponse.class);
			LOGGER.debug("createOPASecret opaSecretVaultResponse ======== " + opaVaultResponse.toString());
		} catch (Exception e) {
			LOGGER.error("createOPASecret >>> "+ e.getMessage());
			// e.printStackTrace();
		}
		return opaVaultResponse;

	}
	
	
	/**
	 * Create secret folder in Okta Vault
	 * 
	 * @param opaPASecretVault
	 * @param apiEndpoint
	 * @param authToken
	 * @return Response from Okta Vault after Secret Creation
	 */
	public OPAVaultResponse createOPASecretFolder(String opaPASecretFolder, String apiEndpoint, String authToken) {
		LOGGER.info("createOPASecretFolder Start Create Secret Folder process");
		OPAVaultResponse opaVaultResponse = null;
		try {
			String responseBody = createSecretFolder(opaPASecretFolder, apiEndpoint, authToken);
			LOGGER.debug("createOPASecretFolder responseBody =============> " + responseBody);
			ObjectMapper mapper = new ObjectMapper();
			opaVaultResponse = mapper.readValue(responseBody, OPAVaultResponse.class);
			LOGGER.debug("createOPASecretFolder opaSecretVaultResponse ======== " + opaVaultResponse.toString());
		} catch (Exception e) {
			LOGGER.error("createOPASecretFolder >>> "+ e.getMessage());
			// e.printStackTrace();
		}
		return opaVaultResponse;

	}

	/**
	 * Get Authorization token to use for other APIs
	 * 
	 * @param apiEndpointURL
	 * @param requestBody
	 * @return String - ResponseBody
	 */
	private String getAuthToken(String apiEndpointURL, String requestBody) {
		LOGGER.info("getAuthToken Fetch auth token for API use");
		Response response = null;
		String responseBody = "";

		try {
			OkHttpClient client = new OkHttpClient().newBuilder().build();
			MediaType mediaType = MediaType.parse(Constants.JASON_CONTENT_TYPE);
			RequestBody body = RequestBody.create(mediaType, requestBody);
			Request request = new Request.Builder().url(apiEndpointURL).method("POST", body)
					.addHeader("Content-Type", Constants.JASON_CONTENT_TYPE).build();
			response = client.newCall(request).execute();
			responseBody = response.body().string().toString().trim();
		} catch (Exception e) {
			LOGGER.error("getAuthToken >>> "+ e.getMessage());
			//e.printStackTrace();
		}
		LOGGER.info("getAuthToken response code ========> " + response.code());
		LOGGER.debug("getAuthToken responseBody  ========> " + responseBody);
		return responseBody;
	}

	/**
	 * Get JWK Public Key from Okta
	 * 
	 * @param apiEndpointURL
	 * @param requestBody
	 * @return String - Response from Okta
	 */
	private String getVaultJWKS(String apiEndpointURL, String authToken) {
		LOGGER.info("getVaultJWKS Getting public Key ");
		Response response = null;
		String responseBody = "";
		try {
			OkHttpClient client = new OkHttpClient().newBuilder().build();
			Request request = new Request.Builder().url(apiEndpointURL).method("GET", null)
					.addHeader("Accept", Constants.JASON_CONTENT_TYPE)
					.addHeader("Content-Type", Constants.JASON_CONTENT_TYPE)
					.addHeader("Authorization", "Bearer " + authToken).build();
			response = client.newCall(request).execute();
			responseBody = response.body().string().toString().trim();
		} catch (Exception e) {
			LOGGER.error("getVaultJWKS >>> "+ e.getMessage());
			//e.printStackTrace();
		}
		LOGGER.info("getVaultJWKS response code ==========> " + response.code());
		LOGGER.debug("getVaultJWKS responseBody  ========> " + responseBody);
		return responseBody;
	}

	/**
	 * Create Secret in Okta Vault
	 * 
	 * @param opaPASecretVault
	 * @param apiEndpoint
	 * @param authToken
	 * @return String - ResponseBody
	 */
	private String createSecret(String opaPASecretVault, String apiEndpoint, String authToken) {
		LOGGER.info("createSecret Creating a Secret in Okta PAM Vault.");
		Response response = null;
		String responseBody = "";
		try {
			OkHttpClient client = new OkHttpClient().newBuilder().build();
			MediaType mediaType = MediaType.parse(Constants.JASON_CONTENT_TYPE);
			RequestBody body = RequestBody.create(mediaType, opaPASecretVault);
			Request request = new Request.Builder().url(apiEndpoint).method("POST", body)
					.addHeader("Content-Type", Constants.JASON_CONTENT_TYPE)
					.addHeader("Accept", Constants.JASON_CONTENT_TYPE)
					.addHeader("Authorization", "Bearer " + authToken)
					.build();
			response = client.newCall(request).execute();
			responseBody = response.body().string().toString().trim();
		} catch (Exception e) {
			LOGGER.error("createSecret >>> "+ e.getMessage());
			//e.printStackTrace();
		}
		LOGGER.info("createSecret response code ========> " + response.code());
		LOGGER.debug("createSecret responseBody  ========> " + responseBody);
		return responseBody;
	}

	/**
	 * Creates a folder in Vault
	 * @param opaPASecretVault
	 * @param apiEndpoint
	 * @param authToken
	 */
	private String createSecretFolder(String opaPASecretVault, String apiEndpoint, String authToken) {
		LOGGER.info("createSecretFolder Creating a Secret folder in Okta PAM Vault.");
		Response response = null;
		String responseBody = "";
		try {
			OkHttpClient client = new OkHttpClient().newBuilder().build();
			MediaType mediaType = MediaType.parse(Constants.JASON_CONTENT_TYPE);
			RequestBody body = RequestBody.create(mediaType,opaPASecretVault);
			Request request = new Request.Builder().url(apiEndpoint)
					.method("POST", body)
					.addHeader("Content-Type", Constants.JASON_CONTENT_TYPE)
					.addHeader("Accept", Constants.JASON_CONTENT_TYPE)
					.addHeader("Authorization", "Bearer " + authToken)
					.build();
			response = client.newCall(request).execute();
			responseBody = response.body().string().toString().trim();
		} catch (Exception e) {
			LOGGER.error("createSecretFolder >>> "+ e.getMessage());
			//e.printStackTrace();
		}
		LOGGER.info("createSecretFolder response code ========> " + response.code());
		LOGGER.debug("createSecretFolder responseBody  ========> " + responseBody);
		return responseBody;
	}

}
