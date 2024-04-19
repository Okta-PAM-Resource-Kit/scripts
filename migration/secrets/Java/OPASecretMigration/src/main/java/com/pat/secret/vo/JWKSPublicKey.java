package com.pat.secret.vo;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Object with OPA public key details
 * @author rajeshkumar
 *
 */

@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public class JWKSPublicKey {
	
	@JsonProperty("use")
	private String use;
	
	@JsonProperty("kty")
	private String kty;
	
	@JsonProperty("kid")
	private String kid;
	
	@JsonProperty("alg")
	private String alg;
	
	@JsonProperty("n")
	private String n;
	
	@JsonProperty("e")
	private String e;

	@JsonProperty("use")
	public String getUse() {
		return use;
	}

	@JsonProperty("use")
	public void setUse(String use) {
		this.use = use;
	}

	@JsonProperty("kty")
	public String getKty() {
		return kty;
	}

	@JsonProperty("kty")
	public void setKty(String kty) {
		this.kty = kty;
	}

	@JsonProperty("kid")
	public String getKid() {
		return kid;
	}

	@JsonProperty("kid")
	public void setKid(String kid) {
		this.kid = kid;
	}

	@JsonProperty("alg")
	public String getAlg() {
		return alg;
	}

	@JsonProperty("alg")
	public void setAlg(String alg) {
		this.alg = alg;
	}

	@JsonProperty("n")
	public String getN() {
		return n;
	}

	@JsonProperty("n")
	public void setN(String n) {
		this.n = n;
	}

	@JsonProperty("e")
	public String getE() {
		return e;
	}

	@JsonProperty("e")
	public void setE(String e) {
		this.e = e;
	}

}
