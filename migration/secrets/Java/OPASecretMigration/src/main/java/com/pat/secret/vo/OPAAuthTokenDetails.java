package com.pat.secret.vo;

import java.util.List;

import org.dozer.Mapping;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Object with Auth token to make OPA API call
 * @author rajeshkumar
 *
 */

@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public class OPAAuthTokenDetails {
	
	@JsonProperty("bearer_token")
	private String bearer_token;
	
	@JsonProperty("expires_at")
	private String expires_at;
	
	@JsonProperty("team_name")
	private String team_name;
	
	@JsonProperty("keys")
	private List<JWKSPublicKey> vaultPublicKey;
	
	@JsonProperty("bearer_token")
	@Mapping("bearer_token")
	public String getBearer_token() {
		return bearer_token;
	}
	
	@JsonProperty("bearer_token")
	public void setBearer_token(String bearer_token) {
		this.bearer_token = bearer_token;
	}
	
	@JsonProperty("expires_at")
	@Mapping("expires_at")
	public String getExpires_at() {
		return expires_at;
	}
	
	@JsonProperty("expires_at")
	public void setExpires_at(String expires_at) {
		this.expires_at = expires_at;
	}
	
	@JsonProperty("team_name")
	@Mapping("team_name")
	public String getTeam_name() {
		return team_name;
	}
	
	@JsonProperty("team_name")
	public void setTeam_name(String team_name) {
		this.team_name = team_name;
	}

	@JsonProperty("keys")
	@Mapping("keys")
	public List<JWKSPublicKey> getVaultPublicKey() {
		return vaultPublicKey;
	}

	@JsonProperty("keys")
	public void setVaultPublicKey(List<JWKSPublicKey> vaultPublicKey) {
		this.vaultPublicKey = vaultPublicKey;
	}
	
	

}
