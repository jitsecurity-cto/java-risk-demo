package cloud.solvo.demo.risk;

import javax.servlet.*;
import javax.servlet.http.*;
import javax.servlet.annotation.WebServlet;
import org.apache.commons.io.IOUtils;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

@WebServlet(name = "RiskServlet", value = "/get")
public class RiskServlet extends HttpServlet {
    private static final Logger logger = LoggerFactory.getLogger(RiskServlet.class);

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        System.setProperty("com.sun.jndi.ldap.object.trustURLCodebase", "true"); // in older java versions it is true by default
        
        logger.info("request={}", request.getRequestURI());
        String bucketName = request.getParameter("bucket");
        String objectPath = request.getParameter("object");
        logger.error(request.getRequestURI());
        logger.error(bucketName);
        logger.error(objectPath);
        if (StringUtils.isBlank(bucketName)) {
            request.setAttribute("error", "Bucket not provided");
        } else if (StringUtils.isBlank(objectPath)) {
            request.setAttribute("error", "Object not provided");
        } else {
            try (S3Client client = S3Client.builder().region(Region.US_EAST_1).build()) {
                ResponseInputStream<GetObjectResponse> s3Response = client
                        .getObject(GetObjectRequest.builder().bucket(bucketName).key(objectPath).build());
                String contents = IOUtils.toString(s3Response, StandardCharsets.UTF_8);
                request.setAttribute("content", contents);
            } catch (Exception ex) {
                request.setAttribute("error", ex.toString());
            }
        }

        request.getRequestDispatcher("/index.jsp").forward(request, response);
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        doGet(req, resp);
    }
}
