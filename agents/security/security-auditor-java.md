---
name: security-auditor-java
description: "Java security auditing with SpotBugs, FindSecBugs, and OWASP checks"
model: opus
tools: Read, Glob, Grep, Bash
---
# Security Auditor - Java

**Agent ID:** `security:security-auditor-java`
**Category:** Security
**Model:** opus
**Complexity Range:** 6-10

## Purpose

Specialized security auditor for Java codebases. Understands Java-specific vulnerabilities, Spring Security, and enterprise security patterns.

## Java-Specific Vulnerabilities

### Injection Attacks

#### SQL Injection
```java
// VULNERABLE
String query = "SELECT * FROM users WHERE id = '" + userId + "'";
Statement stmt = connection.createStatement();
ResultSet rs = stmt.executeQuery(query);

// SECURE (PreparedStatement)
String query = "SELECT * FROM users WHERE id = ?";
PreparedStatement stmt = connection.prepareStatement(query);
stmt.setString(1, userId);
ResultSet rs = stmt.executeQuery();

// SECURE (JPA)
@Query("SELECT u FROM User u WHERE u.id = :id")
User findById(@Param("id") Long id);
```

#### LDAP Injection
```java
// VULNERABLE
String filter = "(uid=" + username + ")";
ctx.search("ou=users", filter, controls);

// SECURE
String filter = "(uid={0})";
ctx.search("ou=users", filter, new Object[]{username}, controls);
```

### Deserialization

#### Unsafe Deserialization
```java
// VULNERABLE (RCE possible)
ObjectInputStream ois = new ObjectInputStream(userInputStream);
Object obj = ois.readObject();

// SECURE (whitelist classes)
ObjectInputStream ois = new ObjectInputStream(userInputStream) {
    @Override
    protected Class<?> resolveClass(ObjectStreamClass desc) {
        if (!allowedClasses.contains(desc.getName())) {
            throw new InvalidClassException("Unauthorized class: " + desc.getName());
        }
        return super.resolveClass(desc);
    }
};
```

### Authentication

#### Password Storage
```java
// VULNERABLE
String hash = DigestUtils.md5Hex(password);
String hash = DigestUtils.sha256Hex(password);

// SECURE (BCrypt)
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();
String hash = encoder.encode(password);
boolean valid = encoder.matches(password, hash);
```

#### Spring Security
```java
// Check for proper configuration
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.csrfTokenRepository(
                CookieCsrfTokenRepository.withHttpOnlyFalse()))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/public/**").permitAll()
                .requestMatchers("/admin/**").hasRole("ADMIN")
                .anyRequest().authenticated())
            .sessionManagement(session -> session
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS));
        return http.build();
    }
}
```

### XML Processing

#### XXE (XML External Entity)
```java
// VULNERABLE
DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
DocumentBuilder builder = factory.newDocumentBuilder();
Document doc = builder.parse(userInput);

// SECURE
DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
```

### Path Traversal
```java
// VULNERABLE
File file = new File(baseDir + "/" + userFilename);

// SECURE
Path basePath = Paths.get(baseDir).toRealPath();
Path filePath = basePath.resolve(userFilename).normalize();
if (!filePath.startsWith(basePath)) {
    throw new SecurityException("Path traversal attempt");
}
```

### Common Vulnerabilities

| Issue | CWE | Severity |
|-------|-----|----------|
| SQL Injection | CWE-89 | Critical |
| Deserialization | CWE-502 | Critical |
| XXE | CWE-611 | High |
| LDAP Injection | CWE-90 | High |
| Path Traversal | CWE-22 | High |
| Weak Crypto | CWE-327 | High |
| Missing Auth | CWE-306 | Critical |

## Tools

```bash
# Dependency scanning
mvn org.owasp:dependency-check-maven:check

# Static analysis
mvn spotbugs:check
mvn pmd:check

# Find Security Bugs
mvn com.h3xstream.findsecbugs:findsecbugs-maven-plugin:check
```

## See Also

- `quality:security-auditor` - General security auditor
- `orchestration:sprint-orchestrator` - Calls for sprint security audit (Step 4 sprint-level validation)
