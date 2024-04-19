package com.pat.secret.vo;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Object to carry OPA request payload
 * @author rajeshkumar
 *
 */

@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public class OPAVaultRequest{
	
	@JsonProperty("name")
	private String name;
	
	@JsonProperty("secret_jwe")
	private String secretJwe;
	
	@JsonProperty("parent_folder_id")
	private String parentFolderId;
	
	@JsonProperty("description")
	private String secretDescription;

	@JsonProperty("name")
	public String getName() {
		return name;
	}

	@JsonProperty("name")
	public void setName(String name) {
		this.name = name;
	}

	@JsonProperty("secret_jwe")
	public String getSecretJwe() {
		return secretJwe;
	}

	@JsonProperty("secret_jwe")
	public void setSecretJwe(String secretJwe) {
		this.secretJwe = secretJwe;
	}

	@JsonProperty("parent_folder_id")
	public String getParentFolderId() {
		return parentFolderId;
	}

	@JsonProperty("parent_folder_id")
	public void setParentFolderId(String parentFolderId) {
		this.parentFolderId = parentFolderId;
	}

	@JsonProperty("description")
	public String getSecretDescription() {
		return secretDescription;
	}

	@JsonProperty("description")
	public void setSecretDescription(String secretDescription) {
		this.secretDescription = secretDescription;
	}

	@Override
	public String toString() {
		return "OPAVaultRequest [name=" + name + ", secretJwe=" + secretJwe + ", parentFolderId="
				+ parentFolderId + ", secretDescription=" + secretDescription + "]";
	}
	
	

}
